import Foundation

/// The recommender engine. Stateless — given the same inputs, produces the same outputs.
/// Per design doc §6.1: takes `GuideLog + RigProfile` (+ optional context) and returns typed
/// observation records.
///
/// Observations are returned in triage order per throughline #11 (mechanical-first):
/// subQuality → opticalTrain → equipment → phd2Hygiene → pattern → suggestion.
/// Within each category, ordered by severity (alert > pattern > … > coaching).
nonisolated struct RecommenderEngine: Sendable {

    /// Generators registered with the engine. Order doesn't matter — the engine sorts the
    /// observations by category/severity after running all generators.
    let generators: [any RecommenderGenerator]

    /// Default engine with all single-night generators registered.
    /// Phase 2 ships single-night only; cross-night generators land in Phase 7.
    static let `default` = RecommenderEngine(generators: [
        // PHD2-canon tier (highest authority)
        GuidingAssistantRecommendationObserver(),
        CalibrationSanityAlertObserver(),
        MaxDurationLimitObserver(),
        CalibrationStalenessObserver(),
        CalibrationOrthogonalityObserver(),
        VariableExposureDelaysObserver(),
        MultiStarGuidingObserver(),
        AlgorithmMismatchObserver(),
        // Ephemeris-heuristic tier (softened voice)
        DecPolarityBiasObserver(),
        AtmosphericConditionsProxy(),
        // Gap-analysis additions (v2 final): data-derived observers that close the
        // matrix in docs/observation-gap-analysis.md.
        StarShapePredictionObserver(),
        PierSideBiasObserver(),
        CooldownSignatureObserver(),
        MinMoveValidationObserver(),
        GuideRateValidationObserver(),
        AggressivenessObserver(),
        DataDrivenAlgorithmHintObserver(),
        GuideScaleMismatchObserver(),
        StarLostObserver(),
    ])

    init(generators: [any RecommenderGenerator]) {
        self.generators = generators
    }

    /// Run all registered generators against a single guide log + rig profile.
    /// Returns observations in triage order.
    func analyze(log: GuideLog, profile: RigProfile) -> [RecommenderObservation] {
        let context = SingleNightContext(log: log, profile: profile)
        var results: [RecommenderObservation] = []
        for generator in generators {
            let observations = generator.observe(context: context)
            results.append(contentsOf: observations)
        }
        return results.sorted { lhs, rhs in
            if lhs.category.rawValue != rhs.category.rawValue {
                return lhs.category.rawValue < rhs.category.rawValue
            }
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity  // higher severity first
            }
            return lhs.title < rhs.title
        }
    }
}

/// Inputs available to a generator at single-night scope.
/// Cross-night generators (Phase 7) get an extended context type.
nonisolated struct SingleNightContext: Sendable {
    let log: GuideLog
    let profile: RigProfile

    /// Convenience: the most recent calibration in the log (last one chronologically).
    var mostRecentCalibration: Calibration? {
        log.calibrations.last
    }

    /// All sessions in the log, regardless of mount/AO.
    var sessions: [GuideSession] {
        log.guideSessions
    }

    /// Per-session stats, computed once per analysis.
    var sessionStats: [(session: GuideSession, stats: SessionStats)] {
        sessions.map { session in
            (session, SessionStatsCalculator.calculate(session, manualExclusionRanges: []))
        }
    }
}

/// Generator contract. Each generator is a small, focused producer of zero-or-more observations.
/// Stateless and Sendable to support future parallel evaluation.
protocol RecommenderGenerator: Sendable {
    /// Stable identifier used for filtering, dismissing, and threshold-tuning per rig.
    nonisolated var identifier: String { get }

    /// Run this generator against the context. Return zero or more observations.
    nonisolated func observe(context: SingleNightContext) -> [RecommenderObservation]
}
