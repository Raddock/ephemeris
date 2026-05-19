import SwiftUI

/// Renders a single `RecommenderObservation` as a disclosable card.
/// Per design doc §5.1: severity-tier color dot, title, summary, disclosure for evidence /
/// contributors / suggested response / source authority badge.
struct ObservationCard: View {
    let observation: RecommenderObservation
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if expanded {
                Divider()
                content
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(severityTint.opacity(0.3), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded.toggle()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(severityTint)
                .frame(width: 9, height: 9)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(observation.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    authorityBadge
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(observation.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !observation.evidence.isEmpty {
                evidenceSection
            }
            if !observation.candidateContributors.isEmpty {
                contributorsSection
            }
            if !observation.suggestedResponse.isEmpty {
                suggestedResponseSection
            }
            if !observation.relatedPHD2Tools.isEmpty {
                phd2ToolsSection
            }
            if !observation.relatedHelpTopicIds.isEmpty {
                helpTopicsSection
            }
        }
        .padding(.leading, 19)  // align with header text after dot
    }

    @ViewBuilder
    private var helpTopicsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Learn more")
            HStack(spacing: 8) {
                ForEach(observation.relatedHelpTopicIds, id: \.self) { topicId in
                    Button {
                        HelpOpener.openByID(topicId)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "questionmark.circle")
                                .font(.caption2)
                            Text(displayTitle(for: topicId))
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
        }
    }

    private func displayTitle(for topicId: String) -> String {
        HelpTopic(rawValue: topicId)?.displayTitle ?? topicId
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Evidence")
            ForEach(observation.evidence, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item.label + ":")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.caption.monospacedDigit())
                    if let detail = item.detail {
                        Text("— \(detail)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Possible contributors")
            ForEach(observation.candidateContributors, id: \.self) { c in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(.secondary)
                    Text(c).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var suggestedResponseSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Suggested response")
            Text(observation.suggestedResponse)
                .font(.caption)
        }
    }

    private var phd2ToolsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("PHD2 tools referenced")
            HStack(spacing: 8) {
                ForEach(observation.relatedPHD2Tools, id: \.self) { tool in
                    Link(destination: tool.manualURL) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption2)
                            Text(tool.canonicalName)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.5)
    }

    private var authorityBadge: some View {
        Text(observation.sourceAuthority.badgeLabel)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(authorityTint.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(authorityTint.opacity(0.4), lineWidth: 0.5))
            .foregroundStyle(authorityTint)
    }

    private var severityTint: Color {
        switch observation.severity {
        case .alert:      return .red
        case .pattern:    return .orange
        case .equipment:  return .yellow
        case .hygiene:    return .blue
        case .suggestion: return .teal
        case .coaching:   return .secondary
        }
    }

    private var authorityTint: Color {
        switch observation.sourceAuthority {
        case .phd2Manual:              return .blue
        case .phd2Measurement:         return .green
        case .phd2BehaviorDocumented:  return .indigo
        case .communityConsensus:      return .orange
        case .ephemerisHeuristic:      return .secondary
        }
    }
}

/// List of observations grouped by category. Used in the document-window inspector
/// and (in Phase 7) the library window's active-observations panel.
struct ObservationsPanel: View {
    let observations: [RecommenderObservation]
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(observations.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if observations.isEmpty {
                Text("No observations on this log.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(observations) { obs in
                        ObservationCard(observation: obs)
                    }
                }
            }
        }
    }
}

#Preview("Observation card — PHD2 manual (calibration)") {
    let profile = RigProfile(currentName: "Edge-10m", mountClass: .encoderBasedPremium, hasHighPrecisionEncoders: true)
    let obs = RecommenderObservation(
        scope: .singleNight,
        rigProfileId: profile.id,
        category: .phd2Hygiene,
        severity: .alert,
        title: "Calibration orthogonality error of 12.2°",
        summary: "The angle between PHD2's measured RA and Dec calibration legs deviates by 12.2° from 90°.",
        evidence: [
            .init(label: "Orthogonality error", value: "12.2°"),
            .init(label: "Threshold (alert)", value: "10°"),
        ],
        candidateContributors: [
            "Calibration started too close to the celestial pole",
            "Mount slop or balance changing the rate between RA and Dec legs",
        ],
        suggestedResponse: "Run the Calibration Assistant on your next session — it slews to the optimum sky position and pre-clears Dec backlash.",
        relatedPHD2Tools: [.calibrationAssistant, .starCross],
        confidence: .high,
        sourceAuthority: .phd2Manual
    )
    return ObservationCard(observation: obs)
        .padding()
        .frame(width: 380)
}
