import Foundation

/// PHD2 guide algorithms with mount-class suitability and PHD2's own recommendation
/// (or deprecation) status. Matches the algorithm dropdown in PHD2's Algorithm tab.
///
/// Reference: https://openphdguiding.org/man/Guide_algorithms.htm
enum PHD2Algorithm: String, Codable, CaseIterable, Sendable {
    case hysteresis
    case resistSwitch
    /// Deprecated per PHD2 manual; treat in historical logs but never recommend.
    case lowpass
    /// PHD2 manual's explicit pick for encoder mounts.
    case lowpass2
    /// PHD2 manual: "not generally recommended".
    case zFilter
    /// RA-only. PHD2 manual: gear/worm with residual PE. Community pick for harmonic.
    case predictivePEC
    /// AO devices only; pass-through.
    case identity

    /// String value that appears in PHD2 log headers ("X guide algorithm = …").
    var logToken: String {
        switch self {
        case .hysteresis:    return "Hysteresis"
        case .resistSwitch:  return "ResistSwitch"
        case .lowpass:       return "LowPass"
        case .lowpass2:      return "Lowpass2"
        case .zFilter:       return "ZFilter"
        case .predictivePEC: return "PPEC"
        case .identity:      return "Identity"
        }
    }

    /// Parse the value from a PHD2 log header's "X/Y guide algorithm = …" line.
    static func fromLogToken(_ token: String) -> PHD2Algorithm? {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return PHD2Algorithm.allCases.first { $0.logToken.caseInsensitiveCompare(normalized) == .orderedSame }
    }

    var displayName: String {
        switch self {
        case .hysteresis:    return "Hysteresis"
        case .resistSwitch:  return "Resist Switch"
        case .lowpass:       return "LowPass (deprecated)"
        case .lowpass2:      return "LowPass2"
        case .zFilter:       return "Z-Filter"
        case .predictivePEC: return "Predictive PEC"
        case .identity:      return "Identity"
        }
    }

    var isDeprecated: Bool { self == .lowpass }

    /// Whether PHD2's manual recommends this algorithm against general use.
    var isAgainstRecommendedByPhd2: Bool {
        self == .lowpass || self == .zFilter
    }
}
