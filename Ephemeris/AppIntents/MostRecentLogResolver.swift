import Foundation
import SwiftData

/// Resolves the most-recent night's `sourceFilePath` for an optional rig UUID.
/// Used by the `OpenMostRecentLogIntent` App Shortcut.
@MainActor
enum MostRecentLogResolver {
    static func resolve(rigUUID: String?) -> String? {
        guard let library = try? EphemerisLibrary() else { return nil }
        let context = ModelContext(library.container)
        // Filter by rig in the predicate, not in memory after a capped fetch —
        // an idle rig whose newest night ranks below the global newest-N would
        // otherwise never resolve.
        let rigID = rigUUID.flatMap { UUID(uuidString: $0) }
        var descriptor = FetchDescriptor<NightRecordEntity>(
            predicate: rigID.map { id in
                #Predicate<NightRecordEntity> { $0.rigProfile?.id == id }
            },
            sortBy: [SortDescriptor(\.nightDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.sourceFilePath
    }
}
