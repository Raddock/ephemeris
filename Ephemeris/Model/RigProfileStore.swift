import Foundation
import Observation
import SwiftData

/// Rig-profile store backed by the library's SwiftData container. SwiftData is
/// the single owner: the editor, the ingest pipeline, MCP, and Spotlight all
/// read and write `RigProfileEntity` through one store, so there is no mirror
/// to drift out of sync (the v2.0 Phase 1 JSON sidecar did exactly that).
///
/// Legacy JSON profiles in `~/Library/Application Support/Ephemeris/Profiles/`
/// are imported once on first launch and the folder is parked as a backup.
@Observable
@MainActor
final class RigProfileStore {
    private(set) var profiles: [RigProfile] = []

    private let container: ModelContainer?
    private let legacyJSONDirectory: URL

    enum StoreError: LocalizedError {
        case libraryUnavailable
        var errorDescription: String? {
            "The library store isn't available, so rig profiles can't be saved. Quit and reopen Ephemeris; if this keeps happening the library may be damaged."
        }
    }

    init(container: ModelContainer?, legacyJSONDirectory: URL? = nil) {
        self.container = container
        self.legacyJSONDirectory = legacyJSONDirectory ?? Self.defaultLegacyDirectory()
        migrateLegacyJSONIfNeeded()
        load()
    }

    static func defaultLegacyDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Ephemeris", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
    }

    /// Refresh the in-memory list from the container. Also picks up upserts made
    /// by the ingest ModelActor on its own context.
    func load() {
        guard let container else {
            profiles = []
            return
        }
        let fetch = FetchDescriptor<RigProfileEntity>(
            sortBy: [SortDescriptor(\.currentName)]
        )
        let entities = (try? container.mainContext.fetch(fetch)) ?? []
        profiles = entities.map(\.asValue)
            .sorted { $0.currentName.localizedCompare($1.currentName) == .orderedAscending }
    }

    /// Insert or update a profile. The `modifiedAt` timestamp is bumped to now.
    func save(_ profile: RigProfile) throws {
        guard let container else { throw StoreError.libraryUnavailable }
        var p = profile
        p.modifiedAt = .now
        let context = container.mainContext
        let pid = p.id
        let fetch = FetchDescriptor<RigProfileEntity>(
            predicate: #Predicate { $0.id == pid }
        )
        if let existing = try context.fetch(fetch).first {
            existing.update(from: p)
        } else {
            context.insert(RigProfileEntity(from: p))
        }
        try context.save()

        if let idx = profiles.firstIndex(where: { $0.id == p.id }) {
            profiles[idx] = p
        } else {
            profiles.append(p)
        }
        profiles.sort { $0.currentName.localizedCompare($1.currentName) == .orderedAscending }
    }

    /// Delete a profile. The entity's cascade rules remove its night records,
    /// and each night cascades its observations, annotations, GA results, and
    /// session records — keeping the delete-rig confirmation dialog's promise.
    func delete(_ profile: RigProfile) throws {
        guard let container else { throw StoreError.libraryUnavailable }
        let context = container.mainContext
        let pid = profile.id
        let fetch = FetchDescriptor<RigProfileEntity>(
            predicate: #Predicate { $0.id == pid }
        )
        if let entity = try context.fetch(fetch).first {
            context.delete(entity)
            try context.save()
        }
        profiles.removeAll { $0.id == profile.id }
    }

    /// Find a profile that matches the given PHD2 profile name (current or historical).
    /// Per §12 Q1 of the design doc: this is auto-association on name match.
    func profile(matchingPHD2Name name: String) -> RigProfile? {
        profiles.first { $0.matches(profileName: name) }
    }

    // MARK: - Legacy JSON migration

    /// One-time import of the v2.0 Phase 1 JSON sidecar. JSON was the canonical
    /// store until this migration, so JSON wins over any mirrored entity. The
    /// folder is then moved aside as a backup so the import never re-runs (a
    /// re-run would overwrite newer SwiftData edits with stale JSON).
    private func migrateLegacyJSONIfNeeded() {
        guard let container else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyJSONDirectory.path) else { return }
        let urls = (try? fm.contentsOfDirectory(at: legacyJSONDirectory, includingPropertiesForKeys: nil)) ?? []
        let jsonURLs = urls.filter { $0.pathExtension == "json" }

        if !jsonURLs.isEmpty {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let context = container.mainContext
            for url in jsonURLs {
                guard let data = try? Data(contentsOf: url),
                      let profile = try? decoder.decode(RigProfile.self, from: data)
                else { continue }
                let pid = profile.id
                let fetch = FetchDescriptor<RigProfileEntity>(
                    predicate: #Predicate { $0.id == pid }
                )
                if let existing = try? context.fetch(fetch).first {
                    existing.update(from: profile)
                } else {
                    context.insert(RigProfileEntity(from: profile))
                }
            }
            do {
                try context.save()
            } catch {
                // The import didn't persist — leave the JSON folder in place so
                // the (idempotent) migration retries on next launch instead of
                // stranding profiles in a backup folder the app never reads.
                NSLog("[RigProfiles] Legacy JSON migration save failed; will retry next launch: %@",
                      error.localizedDescription)
                return
            }
        }

        // Park the folder even when it held no decodable profiles — an empty
        // Profiles/ directory left behind would re-trigger this check forever.
        var backup = legacyJSONDirectory.deletingLastPathComponent()
            .appendingPathComponent("Profiles.migrated-backup", isDirectory: true)
        if fm.fileExists(atPath: backup.path) {
            backup = legacyJSONDirectory.deletingLastPathComponent()
                .appendingPathComponent("Profiles.migrated-backup-\(UUID().uuidString)", isDirectory: true)
        }
        try? fm.moveItem(at: legacyJSONDirectory, to: backup)
    }
}
