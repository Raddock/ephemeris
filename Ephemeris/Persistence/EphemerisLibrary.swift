import Foundation
import SwiftData

/// Top-level facade over the SwiftData library store.
///
/// Per design doc §3.1: the container is attached to the (forthcoming) library `WindowGroup`
/// only — `DocumentGroup` document windows do **not** share this container. Ingest happens
/// via a `ModelActor` that holds its own context against the same URL.
@MainActor
final class EphemerisLibrary {

    let container: ModelContainer

    init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let url = Self.defaultStoreURL()
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        // Phase 3 will register a SchemaMigrationPlan when SchemaV2 lands.
        self.container = try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Upsert the SwiftData mirror of a rig profile. Call after every rig-editor
    /// save: ingest also re-syncs, but only when a log for this rig is re-imported —
    /// without this, MCP tools and Spotlight serve stale optics until then.
    func syncRigProfile(_ profile: RigProfile) {
        let profileId = profile.id
        let fetch = FetchDescriptor<RigProfileEntity>(
            predicate: #Predicate { $0.id == profileId }
        )
        let context = container.mainContext
        if let existing = try? context.fetch(fetch).first {
            existing.update(from: profile)
        } else {
            context.insert(RigProfileEntity(from: profile))
        }
        try? context.save()
    }

    /// Delete the SwiftData mirror of a rig profile. The entity's cascade rules
    /// remove its night records, and each night cascades its observations,
    /// annotations, GA results, and session records — keeping the delete-rig
    /// confirmation dialog's promise.
    func deleteRigProfile(id: UUID) {
        let fetch = FetchDescriptor<RigProfileEntity>(
            predicate: #Predicate { $0.id == id }
        )
        let context = container.mainContext
        if let entity = try? context.fetch(fetch).first {
            context.delete(entity)
            try? context.save()
        }
    }

    static func defaultStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Ephemeris", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Library.store")
    }
}
