import SwiftUI

/// Environment key for the SwiftData-backed library. Nullable so unit tests and previews
/// can run without a live store; views handle the nil case by simply not auto-ingesting.
private struct EphemerisLibraryKey: EnvironmentKey {
    static let defaultValue: EphemerisLibrary? = nil
}

extension EnvironmentValues {
    var ephemerisLibrary: EphemerisLibrary? {
        get { self[EphemerisLibraryKey.self] }
        set { self[EphemerisLibraryKey.self] = newValue }
    }
}
