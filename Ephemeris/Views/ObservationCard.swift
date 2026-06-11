import SwiftUI

/// Renders a single `RecommenderObservation` as a disclosable card.
/// Per design doc §5.1: severity-tier color dot, title, summary, disclosure for evidence /
/// contributors / suggested response / source authority badge.
struct ObservationCard: View {
    let observation: RecommenderObservation
    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded {
                Divider().opacity(0.5)
                content
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(severityTint.opacity(0.35), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            // Severity-color bar on the leading edge — consistent with metric cards
            Rectangle()
                .fill(severityTint)
                .frame(width: 3)
                .clipShape(
                    UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded.toggle()
            }
        }
    }

    /// Header layout follows the macOS HIG pattern for compact list rows
    /// (Mail, Notes, Reminders): the primary text (title) owns the full row width,
    /// with secondary metadata stacked beneath it. The severity color is carried
    /// by the card's leading edge bar so we don't also need a pill flanking the title.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(observation.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            metaRow
            Text(observation.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Compact metadata row: severity label (with color dot) · source-authority badge.
    /// Plain text + small symbols rather than competing capsules — keeps the title
    /// area uncluttered and the labels never truncate.
    private var metaRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(severityTint).frame(width: 6, height: 6)
                Text(observation.severity.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(severityTint)
            }
            Text("·").foregroundStyle(.tertiary)
            authorityBadge
            Spacer(minLength: 0)
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
            // helpTopicsSection is intentionally not shown until the in-app help
            // bundle ships — its links would 404 against an Apple Help anchor
            // that doesn't exist yet.
        }
        // Header text now starts flush with the card edge; expanded content aligns too.
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
        HStack(spacing: 3) {
            Image(systemName: authoritySymbol)
                .font(.caption2)
            Text(observation.sourceAuthority.badgeLabel)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(authorityTint)
    }

    private var authoritySymbol: String {
        switch observation.sourceAuthority {
        case .phd2Manual, .phd2BehaviorDocumented: return "book.closed"
        case .phd2Measurement:                     return "checkmark.seal"
        case .communityConsensus:                  return "person.2"
        case .ephemerisHeuristic:                  return "sparkle"
        }
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
    /// Empty-state copy — the panel serves both the document window (per-log)
    /// and the library (per-range), and "this log" reads wrong in the latter.
    var emptyMessage: String = "Nothing to surface on this log."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if !observations.isEmpty {
                    Text("\(observations.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(severitySummaryTint, in: Capsule())
                }
            }
            if observations.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text(emptyMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
            } else {
                VStack(spacing: 6) {
                    ForEach(observations) { obs in
                        ObservationCard(observation: obs)
                    }
                }
            }
        }
    }

    /// Highest severity present, used to color the count badge.
    private var severitySummaryTint: Color {
        let max = observations.map(\.severity).max() ?? .coaching
        switch max {
        case .alert:      return .red
        case .pattern:    return .orange
        case .equipment:  return .yellow
        case .hygiene:    return .blue
        case .suggestion: return .teal
        case .coaching:   return .secondary
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
