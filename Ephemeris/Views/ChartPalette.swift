import SwiftUI

/// Data-viz accent colors used by the verdict system. Defined once so light and
/// dark tuning happens in one place instead of scattered `Color(red:)` literals.
///
/// The corals are deliberate: "over resolution / elevated" needs a warning red
/// that is visibly softer than `.red`, which stays reserved for "worst". They
/// are the same in both appearances by design — verdict hue is a data encoding,
/// not chrome, and must not shift meaning between modes.
extension Color {
    /// Soft warning red for over-resolution / elevated verdict tints and chips.
    static let verdictCoral = Color(red: 0.95, green: 0.45, blue: 0.45)
    /// Stronger endpoint for the green→orange→red RMS ramp.
    static let verdictRampRed = Color(red: 0.95, green: 0.30, blue: 0.30)
}
