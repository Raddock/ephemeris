import SwiftUI

/// Three-tier verdict pill (sub-pixel green / at-resolution amber / over-resolution coral)
/// rendered against the rig's imaging pixel scale. Per design doc §5.1 / §7.3.
///
/// When the rig profile is not configured for imaging scale, shows a "Configure rig" affordance
/// instead of a verdict — the recommender refuses to claim a verdict it can't compute.
struct ImagingScaleVerdictChip: View {
    let rmsArcsec: Double
    let imagingPixelScale: Double
    var configureAction: (() -> Void)?

    private var verdict: ImagingScale.Verdict {
        ImagingScale.verdict(rmsArcsec: rmsArcsec, imagingPixelScale: imagingPixelScale)
    }

    private var ratio: Double? {
        ImagingScale.ratio(rmsArcsec: rmsArcsec, imagingPixelScale: imagingPixelScale)
    }

    var body: some View {
        if verdict == .unconfigured {
            unconfiguredChip
        } else {
            verdictChip
        }
    }

    @ViewBuilder
    private var verdictChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(verdict.displayLabel)
                .font(.caption.weight(.medium))
            if let r = ratio {
                Text(String(format: "%.2f×", r))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 0.5))
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Imaging scale verdict: \(verdict.displayLabel)")
    }

    @ViewBuilder
    private var unconfiguredChip: some View {
        Button {
            configureAction?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                Text("Configure rig for scale verdict")
            }
            .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Set the imaging focal length and pixel size in the rig profile to enable the imaging-scale verdict.")
    }

    private var tint: Color {
        switch verdict {
        case .subPixel:        return .green
        case .atResolution:    return .orange
        case .overResolution:  return .verdictCoral
        case .unconfigured:    return .secondary
        }
    }

    private var helpText: String {
        guard let r = ratio else { return verdict.displayLabel }
        let pct = Int((r * 100).rounded())
        let scaleStr = String(format: "%.2f", imagingPixelScale)
        switch verdict {
        case .subPixel:
            return "RMS \(pct)% of imaging scale (\(scaleStr)″/px). Stars stay round."
        case .atResolution:
            return "RMS \(pct)% of imaging scale (\(scaleStr)″/px). Borderline — depends on seeing."
        case .overResolution:
            return "RMS \(pct)% of imaging scale (\(scaleStr)″/px). Stars may trail; consider binning or tighter guiding."
        case .unconfigured:
            return ""
        }
    }
}

#Preview("Sub-pixel") {
    ImagingScaleVerdictChip(rmsArcsec: 0.32, imagingPixelScale: 0.8)
        .padding()
}

#Preview("At resolution") {
    ImagingScaleVerdictChip(rmsArcsec: 0.6, imagingPixelScale: 0.8)
        .padding()
}

#Preview("Over resolution") {
    ImagingScaleVerdictChip(rmsArcsec: 1.2, imagingPixelScale: 0.8)
        .padding()
}

#Preview("Unconfigured") {
    ImagingScaleVerdictChip(rmsArcsec: 0.5, imagingPixelScale: 0) { }
        .padding()
}
