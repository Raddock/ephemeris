import Foundation

/// Reference to a PHD2 tool by name + canonical documentation URL.
/// Observations cite these by name to satisfy throughline #4 (reference PHD2 tools by name).
/// Capitalization matches PHD2's manual exactly — these are proper nouns in the recommender's voice.
enum PHD2Tool: String, Codable, CaseIterable, Sendable {
    case calibrationAssistant
    case guidingAssistant
    case calibrationReviewModification
    case driftAlignment
    case staticPolarAlignment
    case polarDriftAlignment
    case autoSelectStars
    case manualGuide
    case starCross
    case meridianFlipCalibration
    case cometTracking
    case lockPositions
    case phd2Server
    case diagnosticImageLogging

    /// The exact label PHD2's UI and manual use.
    var canonicalName: String {
        switch self {
        case .calibrationAssistant:          return "Calibration Assistant"
        case .guidingAssistant:              return "Guiding Assistant"
        case .calibrationReviewModification: return "Calibration Review and Modification"
        case .driftAlignment:                return "Drift Alignment"
        case .staticPolarAlignment:          return "Static Polar Alignment"
        case .polarDriftAlignment:           return "Polar Drift Alignment"
        case .autoSelectStars:               return "Auto-Select Stars"
        case .manualGuide:                   return "Manual Guide"
        case .starCross:                     return "Star Cross Tool"
        case .meridianFlipCalibration:       return "Meridian Flip Calibration Tool"
        case .cometTracking:                 return "Comet Tracking"
        case .lockPositions:                 return "Lock Positions"
        case .phd2Server:                    return "PHD2 Server"
        case .diagnosticImageLogging:        return "Diagnostic Image Logging"
        }
    }

    /// Deep link to the PHD2 manual section for this tool.
    var manualURL: URL {
        let base = "https://openphdguiding.org/man/"
        let anchor: String
        switch self {
        case .calibrationAssistant:          anchor = "Tools.htm#Calibration_Assistant"
        case .guidingAssistant:              anchor = "Tools.htm#Guiding_Assistant"
        case .calibrationReviewModification: anchor = "Tools.htm#Review_Calibration_Data"
        case .driftAlignment:                anchor = "Tools.htm#Drift_Align"
        case .staticPolarAlignment:          anchor = "Tools.htm#Static_Polar_Alignment"
        case .polarDriftAlignment:           anchor = "Tools.htm#Polar_Drift_Align"
        case .autoSelectStars:               anchor = "Tools.htm#Auto_Find_Star"
        case .manualGuide:                   anchor = "Tools.htm#Manual_Guide"
        case .starCross:                     anchor = "Tools.htm#Star_Cross_Test"
        case .meridianFlipCalibration:       anchor = "Tools.htm#Meridian_Flip"
        case .cometTracking:                 anchor = "Tools.htm#Comet_Tracking"
        case .lockPositions:                 anchor = "Tools.htm#Lock_Position"
        case .phd2Server:                    anchor = "Advanced_settings.htm#Server_Tab"
        case .diagnosticImageLogging:        anchor = "Advanced_settings.htm#Global_Tab"
        }
        return URL(string: base + anchor)!
    }
}
