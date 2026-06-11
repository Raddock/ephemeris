import Foundation
import Observation

/// Bulk-import coordinator. Walks a folder, parses every `PHD2_GuideLog_*.txt`,
/// matches against a `RigProfile` by PHD2 profile name, and pipes each log through
/// the SwiftData `LibraryIngestor`. Per design doc §12 Q7 ("Scan a folder of logs").
///
/// Progress is exposed via `@Observable` so the progress sheet can render in real
/// time. Cancellation is checked between files.
@Observable
@MainActor
final class LibraryBulkImporter {

    enum Status: Equatable, Sendable {
        case idle
        case running(currentFile: String, processed: Int, total: Int)
        case completed(Summary)
        case cancelled(Summary)
    }

    struct Summary: Equatable, Sendable {
        var imported: Int = 0
        var skippedExisting: Int = 0           // dedup hit on content hash
        var skippedEmpty: [String] = []        // empty / 0-byte files (PHD2 placeholder logs)
        var errors: [String] = []
        var totalConsidered: Int = 0
        var autoCreatedRigs: [String] = []     // PHD2 profile names auto-created during import
    }

    var status: Status = .idle

    /// True while an import is pending or running. `.idle` counts: the coordinator
    /// installs the importer before `importFolder` flips the status to `.running`.
    var isWorking: Bool {
        switch status {
        case .idle, .running: return true
        case .completed, .cancelled: return false
        }
    }

    private let library: EphemerisLibrary
    private let rigStore: RigProfileStore
    private var currentTask: Task<Void, Never>?

    init(library: EphemerisLibrary, rigStore: RigProfileStore) {
        self.library = library
        self.rigStore = rigStore
    }

    /// Begin importing all PHD2 guide logs in the chosen folder. Recursive: walks
    /// subdirectories. Idempotent: logs already in the store dedup on content hash.
    func importFolder(_ folderURL: URL) {
        guard currentTask == nil else { return }
        currentTask = Task { @MainActor in
            await runImport(folderURL: folderURL)
            currentTask = nil
        }
    }

    func cancel() {
        currentTask?.cancel()
    }

    private func runImport(folderURL: URL) async {
        var summary = Summary()

        // Sandboxed apps need explicit access to the security-scoped URL returned
        // by NSOpenPanel. Without this, FileManager.enumerator silently returns 0
        // results and the importer looks stuck.
        let accessGranted = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { folderURL.stopAccessingSecurityScopedResource() }
        }
        NSLog("[BulkImport] Scanning %@ (sandbox access: %@)",
              folderURL.path, accessGranted ? "granted" : "denied")

        // Persist a security-scoped bookmark so we can reopen logs from this folder
        // after the bulk-import session ends. Without this, the sandbox revokes
        // access and the "Open log" double-click is rejected with "no permission".
        if accessGranted {
            SourceFolderBookmarks.save(folder: folderURL)
        }

        let urls = findGuideLogs(in: folderURL)
        summary.totalConsidered = urls.count
        NSLog("[BulkImport] Found %d PHD2_GuideLog_*.txt files", urls.count)

        guard !urls.isEmpty else {
            if !accessGranted {
                summary.errors.append("Sandbox denied access to the chosen folder. Try a folder you've previously opened, or grant Full Disk Access to Ephemeris in System Settings.")
            } else {
                summary.errors.append("No files matching PHD2_GuideLog_*.txt found in the chosen folder.")
            }
            status = .completed(summary)
            return
        }

        let ingestor = LibraryIngestor(modelContainer: library.container)
        var touchedRigIds: Set<UUID> = []

        for (index, url) in urls.enumerated() {
            if Task.isCancelled {
                status = .cancelled(summary)
                return
            }
            status = .running(currentFile: url.lastPathComponent,
                              processed: index,
                              total: urls.count)

            // Read + decode + parse off the main actor — this is the most expensive
            // CPU work in the app, and the progress window (and every other window)
            // stutters if it runs on main.
            enum Prepared {
                case parsed(data: Data, log: GuideLog)
                case unreadable, empty, notUTF8
            }
            let prepared = await Task.detached(priority: .userInitiated) { () -> Prepared in
                guard let data = try? Data(contentsOf: url) else { return .unreadable }
                guard !data.isEmpty else { return .empty }
                guard let text = String(data: data, encoding: .utf8) else { return .notUTF8 }
                let log = GuideLogParser.parse(text)
                return log.isEmpty ? .empty : .parsed(data: data, log: log)
            }.value

            let data: Data
            let log: GuideLog
            switch prepared {
            case .unreadable:
                summary.errors.append("\(url.lastPathComponent): unreadable")
                continue
            case .empty:
                summary.skippedEmpty.append(url.lastPathComponent)
                continue
            case .notUTF8:
                summary.errors.append("\(url.lastPathComponent): not UTF-8")
                continue
            case .parsed(let d, let l):
                data = d
                log = l
            }

            // Match rig profile by PHD2 profile name; auto-create a stub if none exists.
            // Per the rig-identity-from-log design preference: the PHD2 profile name is
            // immutable identity, so we create profiles automatically rather than asking
            // the user to predeclare them.
            guard let phd2Name = extractProfileName(from: log) else {
                summary.errors.append("\(url.lastPathComponent): no `Equipment Profile = …` line in header")
                continue
            }
            let profile: RigProfile
            if let existing = rigStore.profile(matchingPHD2Name: phd2Name) {
                profile = existing
            } else {
                profile = autoCreateRig(named: phd2Name, prefilledFrom: log)
                summary.autoCreatedRigs.append(phd2Name)
            }

            // Ingest. Cluster rebuilds are deferred to one batch pass per rig below —
            // per-file rebuilds are O(N²) over the whole import.
            do {
                let result = try await ingestor.ingest(
                    log: log,
                    sourceBytes: data,
                    sourceFilePath: url.path,
                    rigProfile: profile,
                    recomputeClusters: false
                )
                touchedRigIds.insert(profile.id)
                if result.didCreate {
                    summary.imported += 1
                } else {
                    summary.skippedExisting += 1
                }
            } catch {
                summary.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !touchedRigIds.isEmpty {
            try? await ingestor.recomputeClusters(rigIds: touchedRigIds)
        }

        NSLog("[BulkImport] Done — imported: %d, dedup: %d, auto-created rigs: %d, empty: %d, errors: %d",
              summary.imported, summary.skippedExisting,
              summary.autoCreatedRigs.count, summary.skippedEmpty.count, summary.errors.count)
        if !summary.autoCreatedRigs.isEmpty {
            NSLog("[BulkImport]   Auto-created rigs: %@",
                  summary.autoCreatedRigs.joined(separator: ", "))
        }
        if !summary.skippedEmpty.isEmpty {
            NSLog("[BulkImport]   Empty files: %@",
                  summary.skippedEmpty.prefix(5).joined(separator: ", ")
                  + (summary.skippedEmpty.count > 5 ? " (and \(summary.skippedEmpty.count - 5) more)" : ""))
        }
        if !summary.errors.isEmpty {
            for err in summary.errors.prefix(10) {
                NSLog("[BulkImport]   ERROR: %@", err)
            }
        }
        status = .completed(summary)
    }

    // MARK: - Helpers

    /// Create a fresh RigProfile keyed off a PHD2 profile name. Pre-populates the
    /// guide-train fields from the log's header (the imaging-train fields and mount
    /// class stay empty; the user fills those in to enable the verdict pipeline).
    private func autoCreateRig(named phd2Name: String, prefilledFrom log: GuideLog) -> RigProfile {
        var rig = RigProfile(currentName: phd2Name)
        if let session = log.guideSessions.last {
            let props = session.headerProperties
            if let fl = props.guideFocalLengthMm { rig.guideFocalLength = fl }
            if let px = props.guideCameraPixelSizeMicrons { rig.guideCameraPixelSize = px }
            if let bin = props.guideBinning { rig.guideBinning = bin }
        }
        try? rigStore.save(rig)
        NSLog("[BulkImport] Auto-created rig \"%@\"", phd2Name)
        return rig
    }

    private func findGuideLogs(in folderURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            // PHD2 guide logs only — skip debug logs (PHD2_DebugLog_*.txt) which are
            // out of scope per design doc §11
            guard name.hasPrefix("PHD2_GuideLog_"),
                  url.pathExtension == "txt"
            else { continue }
            urls.append(url)
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func extractProfileName(from log: GuideLog) -> String? {
        for session in log.guideSessions.reversed() {
            for line in session.rawHeader {
                if let range = line.range(of: "Equipment Profile = ") {
                    let value = String(line[range.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
            }
        }
        return nil
    }
}
