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

        // Primary: against imaging scale when configured
        if imagingPixelScale > 0 {
            let ratio = rmsArcsec / imagingPixelScale
            if ratio < 0.7 { return .subPixel }
            if ratio <= 1.0 { return .atResolution }
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
}
