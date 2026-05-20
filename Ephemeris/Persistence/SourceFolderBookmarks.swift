import Foundation
import AppKit

/// Persists security-scoped folder bookmarks so the app can reopen PHD2 log files
/// after the bulk-import session ends. Without this, the sandbox revokes access to
/// the chosen folder once `stopAccessingSecurityScopedResource()` runs, and any
/// later attempt to open a log file from `NightRecord.sourceFilePath` is rejected
/// with "Operation not permitted" / "does not have permission to open".
///
/// Bookmarks are saved to UserDefaults keyed by absolute folder path. When
/// `openLog(at:)` is asked to open a path, it walks parent directories looking
/// for any folder whose bookmark covers it, resolves that bookmark, starts the
/// security scope, and only then opens the file. If no covering bookmark exists,
/// it falls back to an NSOpenPanel that prompts the user once and saves the
/// resulting bookmark for next time.
enum SourceFolderBookmarks {
    private static let defaultsKey = "SourceFolderBookmarks.v1"

    /// In-memory cache of resolved URLs whose security scope is currently active.
    /// We keep the scope alive for the rest of the app session — opening a document
    /// inside Ephemeris.app needs the scope held by *this* process while the
    /// document window is alive. Releasing too early breaks subsequent reads.
    private static var activeScopes: [URL] = []

    /// Persist a security-scoped bookmark for a folder the user just granted access to.
    /// Idempotent — re-saving an existing folder replaces the prior bookmark with a fresh one.
    static func save(folder url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var store = readStore()
            store[url.path] = data
            writeStore(store)
        } catch {
            NSLog("[Bookmarks] Failed to create folder bookmark for %@ — %@", url.path, error.localizedDescription)
        }
    }

    /// Try to open a PHD2 log inside Ephemeris.app. Returns true on success, false if
    /// the file isn't on disk. Handles security-scope acquisition transparently —
    /// the caller doesn't need to manage the scope itself.
    ///
    /// Flow:
    /// 1. If a stored bookmark covers the file's parent chain, resolve and start scope, then open
    /// 2. Otherwise show an NSOpenPanel pre-positioned at the parent folder asking for access
    /// 3. Save the new bookmark and retry
    @MainActor
    static func openLog(at path: String) -> Bool {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return false
        }
        let fileURL = URL(fileURLWithPath: path)

        if let scoped = resolveScopedURL(coveringPath: path) {
            // Hold the scope open for the session; document windows read the file repeatedly.
            activeScopes.append(scoped)
            openInDocumentViewer(fileURL)
            return true
        }

        // No bookmark covers this file — ask the user to authorize once.
        let folder = fileURL.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.message = "Grant Ephemeris one-time access to the folder containing your PHD2 logs. After you click Grant, double-clicking a night will open its log directly."
        panel.prompt = "Grant Access"

        guard panel.runModal() == .OK, let chosen = panel.url else { return false }
        save(folder: chosen)

        if let scoped = resolveScopedURL(coveringPath: path) {
            activeScopes.append(scoped)
            openInDocumentViewer(fileURL)
            return true
        }
        return false
    }

    /// Open a log directly in Ephemeris's own document viewer (DocumentGroup
    /// route) so the file routes into our parsed `GuideLogDocument` UI rather
    /// than getting handed to TextEdit by LaunchServices.
    ///
    /// Library-as-home flow: when a document is already open we close it first
    /// so each library double-click "drills into" the same window slot rather
    /// than stacking new windows. If the user opens a log via Finder (multi-
    /// document use case), each gets its own window as usual — only library
    /// double-clicks consolidate.
    @MainActor
    private static func openInDocumentViewer(_ url: URL) {
        let controller = NSDocumentController.shared
        // Close any already-open guide-log documents so the library acts as the
        // home view and the document window is a single drill-down slot.
        for doc in controller.documents {
            if doc.fileURL?.pathExtension.lowercased() == "txt" {
                doc.close()
            }
        }
        controller.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSLog("[OpenLog] openDocument failed for %@ — %@",
                      url.path, error.localizedDescription)
            }
        }
    }

    // MARK: - Internals

    /// Returns the resolved (security-scoped, scope-started) folder URL whose path
    /// is a directory ancestor of `path`. Nil if no stored bookmark matches.
    /// Side effect: starts the security scope on the returned URL.
    private static func resolveScopedURL(coveringPath path: String) -> URL? {
        var store = readStore()
        var changed = false
        defer { if changed { writeStore(store) } }

        // Match longest folder path first so nested bookmarks win over their parents.
        for (folderPath, data) in store.sorted(by: { $0.key.count > $1.key.count }) {
            guard path.hasPrefix(folderPath) else { continue }
            var isStale = false
            do {
                let resolved = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    if let refreshed = try? resolved.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        store[folderPath] = refreshed
                        changed = true
                    }
                }
                guard resolved.startAccessingSecurityScopedResource() else {
                    continue
                }
                return resolved
            } catch {
                NSLog("[Bookmarks] Stale bookmark for %@ — %@", folderPath, error.localizedDescription)
                store.removeValue(forKey: folderPath)
                changed = true
            }
        }
        return nil
    }

    private static func readStore() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
    }

    private static func writeStore(_ store: [String: Data]) {
        UserDefaults.standard.set(store, forKey: defaultsKey)
    }
}
