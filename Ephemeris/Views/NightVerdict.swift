import SwiftUI

/// Verdict tier for a single night's RMS — drives the color treatment in the trend
/// chart, recent-nights rows, and metric cards. Centralizes the imaging-scale-aware
/// logic so the UI is consistent.
///
/// When the rig profile has the imaging pixel scale configured, the verdict is
/// computed against that absolute reference (per design doc §5.1). When not
/// configured, we fall back to a rig-relative baseline using the corpus distribution
/// so the UI still has meaningful color rather than collapsing to all-gray.
enum NightVerdict: Sendable {
    case subPixel        // RMS comfortably under imaging scale → stars round
    case atResolution    // RMS near imaging scale → depends on seeing
    case overResolution  // RMS exceeds imaging scale → stars will trail
    case best            // rig-relative: in the bottom quartile of nights
    case typical         // rig-relative: middle 50%
    case elevated        // rig-relative: top quartile
    case worst           // rig-relative: top decile
    case unknown         // RMS = 0 or no data

    var tint: Color {
        switch self {
        case .subPixel, .best:                 return .green
        case .atResolution, .typical:          return .orange
        case .overResolution, .elevated:       return .verdictCoral
        case .worst:                           return .red
        case .unknown:                         return .secondary
        }
    }

    var shortLabel: String {
        switch self {
        case .subPixel:        return "Sub-pixel"
        case .atResolution:    return "At resolution"
        case .overResolution:  return "Over resolution"
        case .best:            return "Best"
        case .typical:         return "Typical"
        case .elevated:        return "Elevated"
        case .worst:           return "Worst"
        case .unknown:         return "—"
        }
    }

    /// Whether this verdict was computed against the imaging scale (vs rig-relative).
    var isImagingScaleAnchored: Bool {
        switch self {
        case .subPixel, .atResolution, .overResolution: return true
        default: return false
        }
    }
}

/// Centralized verdict computation. Takes a single night's RMS and an optional
/// distribution of other nights' RMS values for the rig (used as fallback baseline).
enum NightVerdictCalculator {
    static func verdict(
        rmsArcsec: Double,
        imagingPixelScale: Double,
        rigDistribution: [Double] = []
    ) -> NightVerdict {
        guard rmsArcsec > 0 else { return .unknown }

        // Primary: against imaging scale when configured. ImagingScale.verdict is
        // the single source of the §5.2 tiering — the document window's session
        // chip uses it directly, and the library must agree with that chip for the
        // same RMS (these two copies once diverged and contradicted each other).
        if imagingPixelScale > 0 {
            switch ImagingScale.verdict(rmsArcsec: rmsArcsec, imagingPixelScale: imagingPixelScale) {
            case .subPixel:       return .subPixel
            case .atResolution:   return .atResolution
            case .overResolution: return .overResolution
            case .unconfigured:   return .unknown  // unreachable: scale > 0
            }
        }

        // Fallback: rig-relative tiering
        let sorted = rigDistribution.filter { $0 > 0 }.sorted()
        guard sorted.count >= 4 else { return .unknown }
        let p25 = sorted[sorted.count / 4]
        let p75 = sorted[sorted.count * 3 / 4]
        let p90 = sorted[Int(Double(sorted.count) * 0.90)]
        if rmsArcsec <= p25 { return .best }
        if rmsArcsec <= p75 { return .typical }
        if rmsArcsec <= p90 { return .elevated }
        return .worst
    }

    /// Continuous good→poor colour for a night's RMS, anchored to the imaging
    /// pixel scale. At or under the scale (sub-pixel guiding the imager can't
    /// fault) it is fully green; it ramps through orange just above the scale to
    /// red well past it. Falls back to the rig-relative verdict tint when no
    /// imaging scale is configured.
    static func rmsColor(
        rmsArcsec: Double,
        imagingPixelScale: Double,
        rigDistribution: [Double] = []
    ) -> Color {
        guard rmsArcsec > 0 else { return .secondary }
        guard imagingPixelScale > 0 else {
            return verdict(rmsArcsec: rmsArcsec,
                           imagingPixelScale: 0,
                           rigDistribution: rigDistribution).tint
        }
        // Ramp breakpoints follow the §5.2 verdict tiers (ImagingScale.verdict):
        // solid green through the sub-pixel band, green→orange across at-resolution
        // (0.7–1.0), orange→red once over-resolved.
        let red = Color.verdictRampRed
        let ratio = rmsArcsec / imagingPixelScale
        if ratio < 0.7 { return .green }
        if ratio <= 1.0 { return Color.green.mix(with: .orange, by: (ratio - 0.7) / 0.3) }
        if ratio <= 2.0 { return Color.orange.mix(with: red, by: (ratio - 1.0) / 1.0) }
        return red
    }
}
