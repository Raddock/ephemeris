import Foundation

/// Integrity guard for throughline #4 (Reference PHD2 tools by name — use PHD2's
/// measured numbers, not parallel heuristics).
///
/// Every `Observation` declares where its advice comes from. The UI surfaces this
/// with different visual treatment: `.phd2Manual` and `.phd2Measurement` carry the
/// most rhetorical force; `.communityConsensus` and `.ephemerisHeuristic` are softened.
enum SourceAuthority: String, Codable, CaseIterable, Sendable {
    /// Directly cited from PHD2's manual / Best Practices document.
    /// e.g. "PHD2 recommends LowPass2 for encoder mounts".
    case phd2Manual

    /// PHD2 itself measured this — verbatim from Guiding Assistant / Calibration Assistant log INFO.
    /// e.g. "Guiding Assistant suggested Dec min-move = 0.18 px".
    /// Supersedes any parallel Ephemeris computation.
    case phd2Measurement

    /// PHD2 source/log behavior PHD2 documents as alerts:
    /// the 4 calibration sanity alerts, max-duration limits, star-lost error codes.
    case phd2BehaviorDocumented

    /// Not in PHD2 docs but widely accepted (harmonic-mount tuning, OAG vs guide-scope wisdom).
    /// Observations citing this authority are labeled as "community consensus" in the UI.
    case communityConsensus

    /// Computed from the corpus by Ephemeris itself (rig-relative RMS tiers,
    /// atmospheric conditions proxy, threshold tier multipliers).
    case ephemerisHeuristic

    /// Short label rendered in the UI badge.
    var badgeLabel: String {
        switch self {
        case .phd2Manual:              return "PHD2 docs"
        case .phd2Measurement:         return "PHD2 measured"
        case .phd2BehaviorDocumented:  return "PHD2 alert"
        case .communityConsensus:      return "community consensus"
        case .ephemerisHeuristic:      return "Ephemeris heuristic"
        }
    }

    /// Whether observations of this authority should use a softer rhetorical register.
    var requiresSoftenedVoice: Bool {
        switch self {
        case .communityConsensus, .ephemerisHeuristic: return true
        default: return false
        }
    }
}
