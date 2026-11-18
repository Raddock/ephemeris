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
        // Forum-triage additions (July 2026): patterns the PHD2 maintainers
        // diagnose repeatedly that the matrix didn't cover.
        SettlingFailureObserver(),
        GuideExposureClassObserver(),
        // Stretches where guiding had lost the star, cut out of every other
        // generator's input by SingleNightContext (November 2026).
        LostStarObserver(),
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
        if log.isASIAir {
            results = results.map(Self.notingASIAir)
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

nonisolated extension RecommenderEngine {
    /// Appended to advice that names a PHD2 dialog or tool when the log came
    /// from an ASIAir. Its guiding is PHD2-based, but its settings live in the
    /// ASIAir app, which has none of PHD2's dialogs; the note says so without
    /// naming ASIAir menus Ephemeris can't verify.
    static let asiAirNote = "This log came from an ASIAir, whose guiding is based on PHD2 but is set up in the ASIAir app. The PHD2 dialogs and tools named here aren't part of that app; the matching guide setting in the app, where there is one, is the place to make this change."

    static func notingASIAir(_ observation: RecommenderObservation) -> RecommenderObservation {
        let namesPHD2Control = !observation.relatedPHD2Tools.isEmpty
            || observation.suggestedResponse.contains("Brain")
        guard namesPHD2Control, !observation.suggestedResponse.contains(asiAirNote) else { return observation }
        var noted = observation
        noted.suggestedResponse += "\n\n" + asiAirNote
        return noted
    }
}

/// Inputs available to a generator at single-night scope.
/// Cross-night generators (Phase 7) get an extended context type.
nonisolated struct SingleNightContext: Sendable {
    /// The night as the generators analyze it: each session with any stretch
    /// where guiding had lost the star cut off, and sessions with too little
    /// left dropped (`LostStar.analysisView`). Those stretches aren't guiding
    /// data; `lostStar` reports them instead.
    let log: GuideLog
    /// The log exactly as parsed, for the few generators that must agree with
    /// figures stored from it (the Library's star-shape chip).
    let rawLog: GuideLog
    let profile: RigProfile
    /// Stretches where guiding had lost the star, one per affected session.
    let lostStar: [LostStar.Finding]
    /// Per-session stats over `log`, computed once per analysis.
    let sessionStats: [(session: GuideSession, stats: SessionStats)]

    init(log: GuideLog, profile: RigProfile) {
        let analysis = LostStar.analysisView(of: log)
        self.rawLog = log
        self.log = analysis.log
        self.profile = profile
        self.lostStar = analysis.findings
        self.sessionStats = analysis.log.guideSessions.map { session in
            (session, SessionStatsCalculator.calculate(session, manualExclusionRanges: []))
        }
    }

    /// Convenience: the most recent calibration in the log (last one chronologically).
    var mostRecentCalibration: Calibration? {
        log.calibrations.last
    }

    /// All analyzed sessions, regardless of mount/AO.
    var sessions: [GuideSession] {
        log.guideSessions
    }

    /// Per-session stats over the log as parsed, uncut.
    var rawSessionStats: [(session: GuideSession, stats: SessionStats)] {
        rawLog.guideSessions.map { session in
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
