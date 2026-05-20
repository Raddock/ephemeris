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
        case .overResolution, .elevated:       return Color(red: 0.95, green: 0.45, blue: 0.45)  // coral
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

        // Primary: against imaging scale when configured. RMS at or under one
        // imaging pixel is sub-pixel guiding — the imager can't fault it.
        if imagingPixelScale > 0 {
            let ratio = rmsArcsec / imagingPixelScale
            if ratio <= 1.0 { return .subPixel }
            if ratio <= 1.5 { return .atResolution }
            return .overResolution
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
        let red = Color(red: 0.95, green: 0.30, blue: 0.30)
        let ratio = rmsArcsec / imagingPixelScale
        if ratio <= 1.0 { return .green }
        if ratio <= 1.5 { return Color.green.mix(with: .orange, by: (ratio - 1.0) / 0.5) }
        if ratio <= 2.5 { return Color.orange.mix(with: red, by: (ratio - 1.5) / 1.0) }
        return red
    }
}
