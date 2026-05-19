import Foundation
import AppKit

/// Canonical list of help-topic IDs referenced from observations and the (Phase 4)
/// expanded help bundle. Per design doc §8: symptom-organized, illustrated reference.
///
/// Per design doc §5.3 and §7 of the throughline addendum: deep-link from observation
/// cards uses `NSHelpManager.shared.openHelpAnchor(_:inBook:)` rather than raw
/// `help:anchor=` URLs — the API handles same-anchor relaunch and navigation state
/// more reliably.
enum HelpTopic: String, Sendable {
    case readingTheGuideLog          = "reading-the-guide-log"
    case pixelScaleAndResolution     = "pixel-scale-and-resolution"
    case imageScaleRatio             = "image-scale-ratio"
    case whatTheGuideLogCantTellYou  = "what-the-guide-log-cant-tell-you"
    case differentialFlexure         = "differential-flexure"
    case polarAlignmentFundamentals  = "polar-alignment-fundamentals"
    case calibrationOrthogonality    = "calibration-orthogonality"
    case calibrationStaleness        = "calibration-staleness"
    case guidingAssistant            = "guiding-assistant"
    case calibrationTroubleshooting  = "calibration-troubleshooting"
    case guideAlgorithms             = "guide-algorithms"
    case aggressivenessAndMinMove    = "aggressiveness-and-min-move"
    case maxDurationLimits           = "max-duration-limits"
    case backlashAndUniDirectional   = "backlash-and-uni-directional"
    case commonPatterns              = "common-patterns"
    case opticalTrainHealth          = "optical-train-health"
    case preFlightChecklist          = "pre-flight-checklist"
    case askingForHelpWell           = "asking-for-help-well"
    case variableExposureDelays      = "variable-exposure-delays"
    case multiStarGuiding            = "multi-star-guiding"
    case seeingVsEquipment           = "seeing-vs-equipment"

    var displayTitle: String {
        switch self {
        case .readingTheGuideLog:          return "Reading your guide log"
        case .pixelScaleAndResolution:     return "Pixel scale and imaging resolution"
        case .imageScaleRatio:             return "The image-scale ratio and round stars"
        case .whatTheGuideLogCantTellYou:  return "What the guide log can't tell you"
        case .differentialFlexure:         return "Differential flexure"
        case .polarAlignmentFundamentals:  return "Polar-alignment fundamentals"
        case .calibrationOrthogonality:    return "Calibration orthogonality"
        case .calibrationStaleness:        return "When to recalibrate"
        case .guidingAssistant:            return "The Guiding Assistant"
        case .calibrationTroubleshooting:  return "Calibration troubleshooting"
        case .guideAlgorithms:             return "Guide algorithms — when defaults are right"
        case .aggressivenessAndMinMove:    return "Aggressiveness, min-move, exposure"
        case .maxDurationLimits:           return "Max RA / Dec duration"
        case .backlashAndUniDirectional:   return "Backlash and uni-directional guiding"
        case .commonPatterns:              return "Common patterns (oscillation, drift, settling)"
        case .opticalTrainHealth:          return "Optical-train health"
        case .preFlightChecklist:          return "Pre-flight checklist"
        case .askingForHelpWell:           return "When to ask for help and how"
        case .variableExposureDelays:      return "Variable Exposure Delays"
        case .multiStarGuiding:            return "Multi-star guiding"
        case .seeingVsEquipment:           return "Seeing vs equipment — telling them apart"
        }
    }
}

/// Opens an Ephemeris help topic in Help Viewer.
/// Uses `NSHelpManager.openHelpAnchor(_:inBook:)` per the design doc deep-link guidance.
@MainActor
enum HelpOpener {
    /// Book ID matches the Apple Help bundle's CFBundleHelpBookName.
    private static let bookID = "com.ephemeris.macobservatory.help"

    static func open(_ topic: HelpTopic) {
        NSHelpManager.shared.openHelpAnchor(topic.rawValue, inBook: bookID)
    }

    static func openByID(_ topicID: String) {
        NSHelpManager.shared.openHelpAnchor(topicID, inBook: bookID)
    }
}
