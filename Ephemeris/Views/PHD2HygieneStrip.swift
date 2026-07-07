import SwiftUI
import SwiftData

/// Per design §7.5: three pills surfacing the PHD2-canon hygiene signals at the top
/// of the library detail view. Each pill is clickable; for v2.0 they open the PHD2
/// manual section for the relevant tool. (Future: sendPrompt-style "ask Claude about
/// this tool" affordance per the design.)
struct PHD2HygieneStrip: View {
    let nightRecords: [NightRecordEntity]
    let gaResults: [GAResultEntity]

    var body: some View {
        HStack(spacing: 10) {
            calibrationPill
            guidingAssistantPill
            polarAlignmentPill
        }
    }

    // MARK: - Calibration Assistant

    private var mostRecentCalibrationOrtho: (Double, Date)? {
        // Stored in NightRecordEntity.calibrationData per the Phase 3 schema; for v2.0
        // we surface the most-recent night-level summary instead since the orthogonality
        // is the same across the whole log's calibration block.
        // Fallback: parse the most recent log's header in the future.
        return nil  // TODO: populate when calibrationData round-trip lands
    }

    private var calibrationPill: some View {
        let mostRecentNight = nightRecords.first
        let dayCount: Int? = mostRecentNight.map { record in
            Int(Date().timeIntervalSince(record.nightDate) / 86400)
        }
        let tint: Color = {
            guard let days = dayCount else { return .secondary }
            if days >= 30 { return .red }
            if days >= 14 { return .orange }
            return .green
        }()
        let label: String = {
            guard let days = dayCount else { return "No data" }
            if days < 1 { return "Recent" }
            return "\(days)d ago"
        }()
        return hygienePill(
            icon: "target",
            title: "Calibration",
            value: label,
            tint: tint,
            detail: "Calibration Assistant",
            url: PHD2Tool.calibrationAssistant.manualURL,
            helpHover: "Open PHD2 Calibration Assistant docs"
        )
    }

    // MARK: - Guiding Assistant

    private var guidingAssistantPill: some View {
        let mostRecentGA = gaResults.max(by: { $0.runAt < $1.runAt })
        let dayCount: Int? = mostRecentGA.map { result in
            Int(Date().timeIntervalSince(result.runAt) / 86400)
        }
        let tint: Color = {
            guard let days = dayCount else { return .red }   // never run = pattern severity
            if days >= 90 { return .red }
            if days >= 30 { return .orange }
            return .green
        }()
        let label: String = {
            guard let days = dayCount else { return "Never run" }
            if days < 1 { return "Recent" }
            return "\(days)d ago"
        }()
        return hygienePill(
            icon: "wand.and.stars",
            title: "Guiding Assistant",
            value: label,
            tint: tint,
            detail: mostRecentGA == nil ? "Recommended" : "Last run",
            url: PHD2Tool.guidingAssistant.manualURL,
            helpHover: "Open PHD2 Guiding Assistant docs"
        )
    }

    // MARK: - Polar alignment

    private var polarAlignmentPill: some View {
        let lastPolarError = gaResults
            .compactMap { $0.polarAlignErrorArcmin }
            .last
        let tint: Color = {
            guard let err = lastPolarError else { return .secondary }
            if err > 10 { return .red }
            if err > 5 { return .orange }
            return .green
        }()
        let label: String = {
            guard let err = lastPolarError else { return "Unknown" }
            return String(format: "%.1f′", err)
        }()
        let detail: String = lastPolarError == nil
            ? "No GA measurement"
            : "Last GA reading"
        return hygienePill(
            icon: "location.north.line",
            title: "Polar alignment",
            value: label,
            tint: tint,
            detail: detail,
            url: PHD2Tool.staticPolarAlignment.manualURL,
            helpHover: "Open PHD2 Polar Alignment docs"
        )
    }

    // MARK: - Pill view

    private func hygienePill(icon: String,
                             title: String,
                             value: String,
                             tint: Color,
                             detail: String,
                             url: URL,
                             helpHover: String) -> some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(tint)
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(tint.opacity(0.25), lineWidth: 0.5)
            )
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .help(helpHover)
    }
}
