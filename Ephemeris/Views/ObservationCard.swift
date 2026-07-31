import SwiftUI

/// Renders one `ObservationDisplayItem` as a disclosable card.
///
/// Collapsed, the card is a single title row — the severity is carried by the
/// leading edge bar, and the summary stays behind the disclosure. Seven
/// findings used to fill the whole inspector; title-only rows make the list
/// scannable, and expanding one card gives the full detail (per-axis sections
/// when the item is a merged RA + Dec pair).
struct ObservationCard: View {
    let item: ObservationDisplayItem
    /// When set, the collapsed row shows which session the finding came from
    /// (used on the Summary's night report, where cards from every session mix).
    var sessionTimeLabel: String? = nil
    @State private var expanded: Bool = false

    init(item: ObservationDisplayItem, sessionTimeLabel: String? = nil) {
        self.item = item
        self.sessionTimeLabel = sessionTimeLabel
    }

    /// Convenience for previews and any call site with a bare observation.
    init(observation: RecommenderObservation) {
        self.item = ObservationDisplayItem(primary: observation, paired: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow
            if expanded {
                metaRow
                Divider().opacity(0.5)
                content
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, expanded ? 12 : 9)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.severity.displayName): \(item.title)")
        .accessibilityHint(expanded ? "Collapses the detail" : "Expands the detail")
    }

    /// The whole collapsed card: title and chevron. Severity lives in the edge
    /// bar; everything else waits behind the disclosure.
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(expanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let sessionTimeLabel {
                Text(sessionTimeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    /// Compact metadata row: severity label (with color dot) · source-authority badge.
    private var metaRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(severityTint).frame(width: 6, height: 6)
                Text(item.severity.displayName)
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
            if let ra = item.raObservation, let dec = item.decObservation {
                // Merged pair: the same finding on both axes, one section each.
                axisSection(label: "RA", observation: ra)
                axisSection(label: "Dec", observation: dec)
            } else {
                markdownText(item.primary.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.primary.evidence.isEmpty {
                    evidenceSection(item.primary.evidence)
                }
            }
            if !item.candidateContributors.isEmpty {
                contributorsSection
            }
            if !item.primary.suggestedResponse.isEmpty {
                suggestedResponseSection
            }
            if !item.relatedPHD2Tools.isEmpty {
                phd2ToolsSection
            }
            // helpTopicsSection is intentionally not shown until the in-app help
            // bundle ships — its links would 404 against an Apple Help anchor
            // that doesn't exist yet.
        }
    }

    /// One axis of a merged pair: axis label, that axis's summary, its evidence.
    private func axisSection(label: String, observation: RecommenderObservation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel(label)
            markdownText(observation.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !observation.evidence.isEmpty {
                evidenceRows(observation.evidence)
            }
        }
    }

    private func evidenceSection(_ evidence: [EvidenceItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Evidence")
            evidenceRows(evidence)
        }
    }

    private func evidenceRows(_ evidence: [EvidenceItem]) -> some View {
        ForEach(evidence, id: \.self) { item in
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

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Possible contributors")
            ForEach(item.candidateContributors, id: \.self) { c in
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
            markdownText(item.primary.suggestedResponse)
                .font(.caption)
        }
    }

    /// Generator strings carry inline markdown (**PHD2 control names**, *manual
    /// quotes*). `Text(String)` never parses markdown — only literal
    /// `LocalizedStringKey` initializers do — so without this the asterisks
    /// render literally in the card.
    private func markdownText(_ source: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(source)
    }

    private var phd2ToolsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("PHD2 tools referenced")
            HStack(spacing: 8) {
                ForEach(item.relatedPHD2Tools, id: \.self) { tool in
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
            Text(item.sourceAuthority.badgeLabel)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(authorityTint)
    }

    private var authoritySymbol: String {
        switch item.sourceAuthority {
        case .phd2Manual, .phd2BehaviorDocumented: return "book.closed"
        case .phd2Measurement:                     return "checkmark.seal"
        case .communityConsensus:                  return "person.2"
        case .ephemerisHeuristic:                  return "sparkle"
        }
    }

    private var severityTint: Color {
        Self.tint(for: item.severity)
    }

    static func tint(for severity: RecommenderObservation.Severity) -> Color {
        switch severity {
        case .alert:      return .red
        case .pattern:    return .orange
        case .equipment:  return .yellow
        case .hygiene:    return .blue
        case .suggestion: return .teal
        case .coaching:   return .secondary
        }
    }

    private var authorityTint: Color {
        switch item.sourceAuthority {
        case .phd2Manual:              return .blue
        case .phd2Measurement:         return .green
        case .phd2BehaviorDocumented:  return .indigo
        case .communityConsensus:      return .orange
        case .ephemerisHeuristic:      return .secondary
        }
    }
}

/// List of observations with per-axis pairs folded into single cards. Used in
/// the document-window inspector and the library window's observations panel.
/// The whole panel collapses behind a remembered header disclosure so readers
/// who only want the charts can reclaim the space — the count badge stays
/// visible either way, so nothing is silently missed.
struct ObservationsPanel: View {
    let observations: [RecommenderObservation]
    let title: String
    /// Empty-state copy — the panel serves both the document window (per-log)
    /// and the library (per-range), and "this log" reads wrong in the latter.
    var emptyMessage: String = "Nothing to surface on this log."
    /// Label session-anchored cards with their session start time. On by the
    /// Summary's night report, where cards from different sessions mix; off on
    /// a session's own inspector, where the time would be redundant.
    var showsSessionTimes: Bool = false

    // Collapsed by default: the count badge invites review without the advice
    // stack displacing the log's data on first open.
    @AppStorage("observations.panelCollapsed") private var panelCollapsed = true

    private var items: [ObservationDisplayItem] {
        ObservationPairMerger.displayItems(from: observations)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !panelCollapsed {
                if observations.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 6) {
                        ForEach(items) { item in
                            ObservationCard(item: item, sessionTimeLabel: timeLabel(for: item))
                        }
                    }
                }
            }
        }
    }

    private func timeLabel(for item: ObservationDisplayItem) -> String? {
        guard showsSessionTimes, let start = item.primary.sessionStartedAt else { return nil }
        return Self.sessionTimeFormatter.string(from: start)
    }

    private static let sessionTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if !observations.isEmpty {
                Text("\(items.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(severitySummaryTint, in: Capsule())
            }
            Image(systemName: panelCollapsed ? "chevron.right" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                panelCollapsed.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(observations.isEmpty
            ? title
            : "\(title), \(items.count) observation\(items.count == 1 ? "" : "s")")
        .accessibilityHint(panelCollapsed ? "Shows the observations" : "Hides the observations")
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
    }

    /// Highest severity present, used to color the count badge.
    private var severitySummaryTint: Color {
        ObservationCard.tint(for: observations.map(\.severity).max() ?? .coaching)
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

#Preview("Observations panel — merged RA + Dec pair") {
    let profile = RigProfile(currentName: "Edge-10m")
    func sluggish(_ axis: String, lag: String) -> RecommenderObservation {
        RecommenderObservation(
            scope: .singleNight,
            rigProfileId: profile.id,
            category: .pattern,
            severity: .pattern,
            title: "\(axis) corrections appear sluggish",
            summary: "Lag-1 autocorrelation of \(axis) corrections is \(lag). Strongly positive autocorrelation means each move repeats the last one instead of responding to fresh error.",
            evidence: [.init(label: "Lag-1 autocorrelation", value: lag)],
            candidateContributors: ["Aggressiveness set too low", "Lowpass2 smoothing too heavy"],
            suggestedResponse: "Try raising the aggressiveness a notch on your next session and compare.",
            sourceAuthority: .ephemerisHeuristic
        )
    }
    return ObservationsPanel(
        observations: [
            sluggish("Dec", lag: "+0.47"),
            sluggish("RA", lag: "+0.41"),
        ],
        title: "Observations · Edge-10m"
    )
    .padding()
    .frame(width: 380)
}
