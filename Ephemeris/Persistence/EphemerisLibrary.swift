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

    /// Deletes every ingested night and everything hanging off it (observations,
    /// annotations, GA results, session records) plus target clusters. Rig
    /// profiles stay.
    ///
    /// Deletes object by object on the main context, the one the Library
    /// window's `@Query`s read. `ModelContext.delete(model:)` is a store-level
    /// batch delete that bypasses the context: an open Library window kept its
    /// fetched nights, their session rows were gone from the store, and the
    /// next redraw trapped reading `SessionRecordEntity.rmsRAArcsec`. Deleting
    /// through the context marks each object deleted, so the queries drop them
    /// before anything reads them. Children go first so nothing is left for a
    /// cascade to fault in; the night's cascade rules still cover any stragglers.
    func resetLibraryData() throws {
        let context = container.mainContext
        func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
            for object in try context.fetch(FetchDescriptor<T>()) {
                context.delete(object)
            }
        }
        try deleteAll(ObservationEntity.self)
        try deleteAll(AnnotationEntity.self)
        try deleteAll(GAResultEntity.self)
        try deleteAll(SessionRecordEntity.self)
        try deleteAll(TargetClusterEntity.self)
        try deleteAll(NightRecordEntity.self)
        try context.save()
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
