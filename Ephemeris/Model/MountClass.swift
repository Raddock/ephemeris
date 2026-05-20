import Foundation

/// Mount classification that drives algorithm/exposure/min-move recommendations.
///
/// The PHD2 manual recognizes three classes by name plus AO. The harmonic strain-wave
/// class is community-consensus territory — the manual is silent. Per throughline #4
/// (secondary clause), any observation citing `.harmonicStrainWave` advice must label
/// its `sourceAuthority` as `.communityConsensus`.
nonisolated enum MountClass: String, Codable, CaseIterable, Sendable {
    /// Worm-and-gear / belt — PHD2's default class.
    case standardGearMount

    /// 10Micron, AP encoder, Planewave, ASA. PHD2's New Profile Wizard exposes this
    /// via the "high-precision encoders" checkbox. The manual explicitly recommends
    /// LowPass2 + Variable Exposure Delays for this class.
    case encoderBasedPremium

    /// ZWO AM5/AM3, iOptron HEM/HAE, Pegasus NYX, WarpAstron. PHD2 manual is silent;
    /// recommender advice is community/vendor consensus.
    case harmonicStrainWave

    /// SX AO, ONAG, Innovations Foresight. Algorithm dropdown collapses to AO-only.
    case adaptiveOptics

    var displayName: String {
        switch self {
        case .standardGearMount:   return "Standard gear / belt mount"
        case .encoderBasedPremium: return "Encoder-based premium mount"
        case .harmonicStrainWave:  return "Harmonic strain-wave mount"
        case .adaptiveOptics:      return "Adaptive optics device"
        }
    }

    /// Whether PHD2's own documentation covers this class explicitly.
    /// `.harmonicStrainWave` returns false — its guidance must be sourced as community consensus.
    var hasPhd2DocumentedGuidance: Bool {
        switch self {
        case .harmonicStrainWave: return false
        default:                  return true
        }
    }
}

/// Mount-class × algorithm recommendation matrix (design doc §4).
/// Each row is consulted by `algorithmMismatchObserver` and the rig-profile editor.
nonisolated struct MountClassDefaults: Sendable {
    var recommendedRAAlgorithm: PHD2Algorithm
    var recommendedDecAlgorithm: PHD2Algorithm
    var recommendedExposureRangeSec: ClosedRange<Double>
    var backlashCompensationOff: Bool
    var variableExposureDelaysOn: Bool
    var sourceAuthority: SourceAuthority

    static func defaults(for mountClass: MountClass) -> MountClassDefaults {
        switch mountClass {
        case .standardGearMount:
            return MountClassDefaults(
                recommendedRAAlgorithm: .hysteresis,
                recommendedDecAlgorithm: .resistSwitch,
                recommendedExposureRangeSec: 1.0...3.0,
                backlashCompensationOff: false,
                variableExposureDelaysOn: false,
                sourceAuthority: .phd2Manual
            )
        case .encoderBasedPremium:
            return MountClassDefaults(
                recommendedRAAlgorithm: .lowpass2,
                recommendedDecAlgorithm: .lowpass2,
                recommendedExposureRangeSec: 4.0...8.0,
                backlashCompensationOff: true,
                variableExposureDelaysOn: true,
                sourceAuthority: .phd2Manual
            )
        case .harmonicStrainWave:
            return MountClassDefaults(
                recommendedRAAlgorithm: .predictivePEC,
                recommendedDecAlgorithm: .resistSwitch,
                recommendedExposureRangeSec: 0.5...1.0,
                backlashCompensationOff: true,
                variableExposureDelaysOn: false,
                sourceAuthority: .communityConsensus
            )
        case .adaptiveOptics:
            return MountClassDefaults(
                recommendedRAAlgorithm: .hysteresis,
                recommendedDecAlgorithm: .hysteresis,
                recommendedExposureRangeSec: 0.1...1.0,
                backlashCompensationOff: true,
                variableExposureDelaysOn: false,
                sourceAuthority: .phd2Manual
            )
        }
    }
}
