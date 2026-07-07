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
        // The migration plan is registered now (empty stages) so the first real
        // schema change only adds a stage instead of retrofitting the plumbing.
        self.container = try ModelContainer(
            for: schema,
            migrationPlan: LibraryMigrationPlan.self,
            configurations: [configuration]
        )
    }

    // Rig-profile reads and writes go through RigProfileStore, which owns
    // RigProfileEntity directly — the old mirror-sync helpers are gone with
    // the JSON sidecar.

    static func defaultStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Ephemeris", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Library.store")
    }
}
