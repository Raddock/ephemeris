import Foundation

/// Imaging-pixel-scale calculation + verdict tiering.
///
/// Formula: arcsec/px = 206.265 × pixel_size_μm × binning / (focal_length_mm × reducer_factor)
/// Reducer factor < 1 shortens effective focal length (faster system); nil treats as 1.0.
nonisolated enum ImagingScale {

    /// Compute pixel scale in arcsec/px. Returns 0 when inputs are insufficient.
    /// 206.265 is the constant arcseconds-per-radian / (1000 μm/mm) for the standard form.
    static func compute(
        focalLengthMm: Double,
        pixelSizeMicrons: Double,
        binning: Int,
        reducerFactor: Double?
    ) -> Double {
        guard focalLengthMm > 0, pixelSizeMicrons > 0, binning > 0 else { return 0 }
        let effectiveFL = focalLengthMm * (reducerFactor ?? 1.0)
        guard effectiveFL > 0 else { return 0 }
        return 206.265 * pixelSizeMicrons * Double(binning) / effectiveFL
    }

    /// Verdict tier for a session's RMS relative to a rig's imaging pixel scale.
    /// Tiers per design doc §5.2 (three-color pill: sub-pixel green / at-resolution amber / over-resolution coral).
    enum Verdict: String, Sendable {
        /// RMS comfortably under imaging scale — stars stay round.
        case subPixel
        /// RMS near imaging scale — depends on seeing/conditions.
        case atResolution
        /// RMS exceeds imaging scale — stars will trail.
        case overResolution
        /// Imaging scale not configured; verdict unavailable.
        case unconfigured

        var displayLabel: String {
            switch self {
            case .subPixel:        return "Sub-pixel"
            case .atResolution:    return "At resolution"
            case .overResolution:  return "Over resolution"
            case .unconfigured:    return "—"
            }
        }
    }

    /// Verdict thresholds (relative to imaging pixel scale):
    /// - ratio < 0.7 → sub-pixel
    /// - 0.7 ≤ ratio ≤ 1.0 → at-resolution
    /// - ratio > 1.0 → over-resolution
    static func verdict(rmsArcsec: Double, imagingPixelScale: Double) -> Verdict {
        guard imagingPixelScale > 0 else { return .unconfigured }
        let ratio = rmsArcsec / imagingPixelScale
        if ratio < 0.7 { return .subPixel }
        if ratio <= 1.0 { return .atResolution }
        return .overResolution
    }

    /// Ratio of session RMS (arcsec) to imaging pixel scale.
    /// `ratio == 1.0` means RMS equals one imaging pixel; > 1.0 means the imager is over-resolved.
    static func ratio(rmsArcsec: Double, imagingPixelScale: Double) -> Double? {
        guard imagingPixelScale > 0 else { return nil }
        return rmsArcsec / imagingPixelScale
    }
}
