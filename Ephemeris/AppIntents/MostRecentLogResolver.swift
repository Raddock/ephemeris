import Foundation
import SwiftData

/// Resolves the most-recent night's `sourceFilePath` for an optional rig UUID.
/// Used by the `OpenMostRecentLogIntent` App Shortcut.
@MainActor
enum MostRecentLogResolver {
    static func resolve(rigUUID: String?) -> String? {
        guard let library = try? EphemerisLibrary() else { return nil }
        let context = ModelContext(library.container)
        var descriptor = FetchDescriptor<NightRecordEntity>(
            sortBy: [SortDescriptor(\.nightDate, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        guard let nights = try? context.fetch(descriptor) else { return nil }

        let rigID = rigUUID.flatMap { UUID(uuidString: $0) }
        let match = nights.first { night in
            guard let rigID else { return true }
            return night.rigProfile?.id == rigID
        }
        return match?.sourceFilePath
    }
}
