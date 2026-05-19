import SwiftUI
import Observation

/// Shared @Observable coordinator that holds the currently-active bulk importer.
/// Used so the LibraryWindow can spawn an import and a separate Import-Progress
/// Window scene can pick up the same importer instance.
///
/// Replaces the broken .sheet-based progress UI (macOS sheet sizing was collapsing
/// the content to ~120×120 even with explicit .frame on Tahoe).
@Observable
@MainActor
final class ImportCoordinator {
    /// The active import session, if any. Set when the user picks a folder; cleared
    /// when the user dismisses the progress window.
    var active: LibraryBulkImporter?

    init() {}
}

private struct ImportCoordinatorKey: EnvironmentKey {
    static let defaultValue: ImportCoordinator? = nil
}

extension EnvironmentValues {
    var importCoordinator: ImportCoordinator? {
        get { self[ImportCoordinatorKey.self] }
        set { self[ImportCoordinatorKey.self] = newValue }
    }
}
