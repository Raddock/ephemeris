import SwiftUI

/// User-reported imaging-quality assessment for a night, per design doc §6.2 / Phase 10.
/// The imaging frame is ground truth that the guide log can't see — differential flexure
/// can produce a great guide RMS and trailed subs simultaneously. This is the testimony
/// that closes the trust gap between guide RMS and image quality.
enum SubQualityVerdict: String, Codable, CaseIterable, Sendable {
    case round              // stars round across the field — guide RMS reflects reality
    case slightlyElongated  // mild egg shape — atmosphere or borderline tracking
    case trailed            // obvious trailing — guide RMS is lying about the actual result
    case mixed              // some frames good, some bad — variable conditions

    var displayName: String {
        switch self {
        case .round:             return "Round"
        case .slightlyElongated: return "Slightly elongated"
        case .trailed:           return "Trailed"
        case .mixed:             return "Mixed"
        }
    }

    var symbolName: String {
        switch self {
        case .round:             return "circle.fill"
        case .slightlyElongated: return "oval.fill"
        case .trailed:           return "line.diagonal"
        case .mixed:             return "circle.lefthalf.filled"
        }
    }

    var tint: Color {
        switch self {
        case .round:             return .green
        case .slightlyElongated: return .orange
        case .trailed:           return .red
        case .mixed:             return .yellow
        }
    }

    /// Whether this rating indicates the imaging result diverged from what the guide
    /// log suggests. Used by `SubQualityDiscrepancyObserver` to fire when guide RMS is
    /// sub-pixel but the user reported `.trailed`.
    var isTrailedOrWorse: Bool {
        switch self {
        case .trailed, .mixed:   return true
        default:                 return false
        }
    }
}
