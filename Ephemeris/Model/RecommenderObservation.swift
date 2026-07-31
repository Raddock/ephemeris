import Foundation

/// A typed analytical finding produced by the recommender engine.
/// Per design doc §4 (referred to there as `Observation`) and throughlines #1 (don't overclaim)
/// and #4 (cite PHD2 by name).
///
/// Named `RecommenderObservation` in Swift to avoid shadowing Apple's `Observation` framework
/// (the home of `@Observable`). Both single-night and cross-night observations use this same
/// schema; `sourceAuthority` is the integrity guard that distinguishes canon from heuristic.
nonisolated struct RecommenderObservation: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var scope: Scope
    var rigProfileId: UUID
    /// Single-night observations carry one ID; cross-night carry many.
    var nightRecordIds: [UUID]
    /// Start time of the guide session this observation was derived from, when
    /// the generator's evidence comes from exactly one session. Nil for
    /// night-level findings (aggregates, configuration checks) — those belong
    /// to the whole log, not to any one session's inspector.
    var sessionStartedAt: Date?
    var category: Category
    var severity: Severity
    /// Short, scannable. *"Most sessions exceed imaging resolution"* not *"Your guiding is bad"*.
    var title: String
    /// 1-2 sentences stating the measurement and key context.
    var summary: String
    /// 3-5 bullet items, each a measurable fact. Numbers wherever possible.
    var evidence: [EvidenceItem]
    /// Always plural when present. *"Possible contributors: …"*. Never single-cause.
    var candidateContributors: [String]
    /// Coaching voice, never imperative. References PHD2 tools by name when applicable.
    var suggestedResponse: String
    var relatedHelpTopicIds: [String]
    var relatedPHD2Tools: [PHD2Tool]
    var confidence: Confidence
    var sourceAuthority: SourceAuthority
    var generatedAt: Date
    var dismissedAt: Date?

    init(
        id: UUID = UUID(),
        scope: Scope,
        rigProfileId: UUID,
        nightRecordIds: [UUID] = [],
        sessionStartedAt: Date? = nil,
        category: Category,
        severity: Severity,
        title: String,
        summary: String,
        evidence: [EvidenceItem] = [],
        candidateContributors: [String] = [],
        suggestedResponse: String,
        relatedHelpTopicIds: [String] = [],
        relatedPHD2Tools: [PHD2Tool] = [],
        confidence: Confidence = .medium,
        sourceAuthority: SourceAuthority,
        generatedAt: Date = .now,
        dismissedAt: Date? = nil
    ) {
        self.id = id
        self.scope = scope
        self.rigProfileId = rigProfileId
        self.nightRecordIds = nightRecordIds
        self.sessionStartedAt = sessionStartedAt
        self.category = category
        self.severity = severity
        self.title = title
        self.summary = summary
        self.evidence = evidence
        self.candidateContributors = candidateContributors
        self.suggestedResponse = suggestedResponse
        self.relatedHelpTopicIds = relatedHelpTopicIds
        self.relatedPHD2Tools = relatedPHD2Tools
        self.confidence = confidence
        self.sourceAuthority = sourceAuthority
        self.generatedAt = generatedAt
        self.dismissedAt = dismissedAt
    }

    enum Scope: String, Codable, Sendable {
        case singleNight
        case crossNight
    }

    enum Confidence: String, Codable, Sendable {
        case high, medium, low
    }

    /// Categories in priority order from throughline #11 (mechanical-first triage).
    /// The engine returns observations in this category order, with severity tiers within each.
    enum Category: Int, Codable, Sendable, CaseIterable {
        /// Sub-imaging quality discrepancies (Phase 9: sub-quality feedback loop).
        case subQuality = 0
        /// Multi-star count, HFD, star mass, SNR floor patterns. Optical-train health.
        case opticalTrain = 1
        /// Calibration angle drift, baseline rotation, suspected state changes.
        case equipment = 2
        /// Calibration freshness, GA recency, profile mismatch — PHD2's own alerts.
        case phd2Hygiene = 3
        /// Drift, polarity, oscillation patterns across the corpus.
        case pattern = 4
        /// Imaging-side decisions like binning, integration time.
        case suggestion = 5

        var displayName: String {
            switch self {
            case .subQuality:   return "Sub-quality"
            case .opticalTrain: return "Optical train"
            case .equipment:    return "Equipment"
            case .phd2Hygiene:  return "PHD2 hygiene"
            case .pattern:      return "Pattern"
            case .suggestion:   return "Suggestion"
            }
        }
    }

    /// Severity tiers from design doc §4.
    enum Severity: Int, Codable, Sendable, Comparable {
        /// Strong evidence of a genuine problem (rare).
        case alert = 5
        /// Observed, named pattern requiring user judgment.
        case pattern = 4
        /// Optical-train or mechanical category.
        case equipment = 3
        /// PHD2 tool freshness or configuration.
        case hygiene = 2
        /// Imaging-side decisions.
        case suggestion = 1
        /// Process improvements within normal operation.
        case coaching = 0

        var displayName: String {
            switch self {
            case .alert:      return "Alert"
            case .pattern:    return "Pattern"
            case .equipment:  return "Equipment"
            case .hygiene:    return "Hygiene"
            case .suggestion: return "Suggestion"
            case .coaching:   return "Coaching"
            }
        }

        nonisolated static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

/// One evidence bullet attached to an `Observation`. Includes a label and a measured value.
nonisolated struct EvidenceItem: Codable, Hashable, Sendable {
    var label: String
    var value: String
    var detail: String?

    init(label: String, value: String, detail: String? = nil) {
        self.label = label
        self.value = value
        self.detail = detail
    }
}
