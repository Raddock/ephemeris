import Foundation

/// Value-type rollup of a `NightRecord` for cross-night generators. Built from either
/// the SwiftData `NightRecordEntity` (production) or synthesized in tests. Keeps the
/// generator surface pure and easily testable.
struct NightSummary: Sendable, Identifiable {
    let id: UUID
    let nightDate: Date
    let sessionsCount: Int
    let totalIntegrationMinutes: Double
    let medianRMSArcsec: Double
    let bestSessionRMSArcsec: Double
    let worstSessionRMSArcsec: Double
    /// Median orthogonality error across the calibrations on this night, if present.
    let calibrationOrthogonalityDeg: Double?
    /// Did a Guiding Assistant run during this night? Used by GAFreshnessObserver.
    let guidingAssistantRan: Bool
    /// Phase 10: user-reported imaging-frame quality. Surfaces the throughline #9
    /// "imaging frame is ground truth" signal that the guide log alone can't see.
    let subQuality: SubQualityVerdict?

    init(id: UUID = UUID(),
         nightDate: Date,
         sessionsCount: Int = 0,
         totalIntegrationMinutes: Double = 0,
         medianRMSArcsec: Double = 0,
         bestSessionRMSArcsec: Double = 0,
         worstSessionRMSArcsec: Double = 0,
         calibrationOrthogonalityDeg: Double? = nil,
         guidingAssistantRan: Bool = false,
         subQuality: SubQualityVerdict? = nil) {
        self.id = id
        self.nightDate = nightDate
        self.sessionsCount = sessionsCount
        self.totalIntegrationMinutes = totalIntegrationMinutes
        self.medianRMSArcsec = medianRMSArcsec
        self.bestSessionRMSArcsec = bestSessionRMSArcsec
        self.worstSessionRMSArcsec = worstSessionRMSArcsec
        self.calibrationOrthogonalityDeg = calibrationOrthogonalityDeg
        self.guidingAssistantRan = guidingAssistantRan
        self.subQuality = subQuality
    }

    @MainActor
    init(entity: NightRecordEntity) {
        self.id = entity.id
        self.nightDate = entity.nightDate
        self.sessionsCount = entity.sessionsCount
        self.totalIntegrationMinutes = entity.totalIntegrationMinutes
        self.medianRMSArcsec = entity.medianRMSArcsec
        self.bestSessionRMSArcsec = entity.bestSessionRMSArcsec
        self.worstSessionRMSArcsec = entity.worstSessionRMSArcsec
        self.calibrationOrthogonalityDeg = nil  // Phase 7+ will extract from calibrationData
        self.guidingAssistantRan = (entity.gaResults?.isEmpty == false)
        self.subQuality = entity.subQualityRaw.flatMap { SubQualityVerdict(rawValue: $0) }
    }
}

/// Inputs available to cross-night generators.
struct CrossNightContext: Sendable {
    let profile: RigProfile
    /// Nights sorted chronologically (oldest first). Empty corpus is valid input —
    /// generators return zero observations in that case.
    let nights: [NightSummary]
    let annotations: [Annotation]

    /// Median RMS across the corpus — used by `rigBaselineRMSArcsec` for tier computation.
    var rigBaselineMedianRMS: Double? {
        let vals = nights.map { $0.medianRMSArcsec }.filter { $0 > 0 }.sorted()
        guard !vals.isEmpty else { return nil }
        return vals[vals.count / 2]
    }

    /// p75 RMS across the corpus.
    var rigP75RMS: Double? {
        let vals = nights.map { $0.medianRMSArcsec }.filter { $0 > 0 }.sorted()
        guard vals.count >= 4 else { return nil }
        return vals[Int(Double(vals.count) * 0.75)]
    }

    /// p90 RMS across the corpus.
    var rigP90RMS: Double? {
        let vals = nights.map { $0.medianRMSArcsec }.filter { $0 > 0 }.sorted()
        guard vals.count >= 5 else { return nil }
        return vals[Int(Double(vals.count) * 0.90)]
    }
}

/// Cross-night generator contract — parallel to RecommenderGenerator but consumes
/// `CrossNightContext` instead of `SingleNightContext`.
protocol CrossNightGenerator: Sendable {
    var identifier: String { get }
    func observe(context: CrossNightContext) -> [RecommenderObservation]
}

/// Cross-night variant of the recommender engine. Runs registered cross-night generators
/// against the rolled-up corpus. Per design doc §6.4 (triage ordering): observations
/// are sorted by category then severity.
struct CrossNightEngine: Sendable {
    let generators: [any CrossNightGenerator]

    static let `default` = CrossNightEngine(generators: [
        CalibrationAngleShiftObserver(),
        GAFreshnessObserver(),
        SubQualityDiscrepancyObserver(),
        BaselineRegressionObserver(),
    ])

    init(generators: [any CrossNightGenerator]) {
        self.generators = generators
    }

    func analyze(context: CrossNightContext) -> [RecommenderObservation] {
        let suppressedKinds = AnnotationSuppression.suppressedKinds(from: context.annotations,
                                                                     within: nights(of: context))
        var results: [RecommenderObservation] = []
        for generator in generators {
            // Skip generators the user has explicitly silenced via annotation
            if suppressedKinds.contains(generator.identifier) { continue }
            results.append(contentsOf: generator.observe(context: context))
        }
        return results.sorted { lhs, rhs in
            if lhs.category.rawValue != rhs.category.rawValue {
                return lhs.category.rawValue < rhs.category.rawValue
            }
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return lhs.title < rhs.title
        }
    }

    private func nights(of context: CrossNightContext) -> [Date] {
        context.nights.map { $0.nightDate }
    }
}

/// Per design doc §9: a "new calibration" annotation should silence calibrationAngleShift
/// for the boundary night. This module maps annotation categories to generator identifiers
/// that the annotation explains.
enum AnnotationSuppression {
    /// Map of annotation category → set of generator identifiers that category suppresses.
    /// When an annotation in the time window has one of these categories, the matching
    /// generators are skipped (the user has already explained the event).
    static let categoryToSuppressedGenerators: [AnnotationCategory: Set<String>] = [
        .calibration: ["calibrationAngleShiftObserver", "calibrationStalenessObserver", "calibrationOrthogonalityObserver"],
        .equipment:   ["calibrationAngleShiftObserver", "baselineRegressionObserver"],
        .software:    ["algorithmMismatchObserver"],
    ]

    /// Compute the set of generator identifiers to skip given the corpus's annotations
    /// and the night dates being analyzed. An annotation suppresses its mapped generators
    /// only within ±3 nights of the annotation date, so an old calibration annotation
    /// doesn't permanently silence future cal-staleness observations.
    static func suppressedKinds(from annotations: [Annotation], within nightDates: [Date]) -> Set<String> {
        guard !annotations.isEmpty, !nightDates.isEmpty else { return [] }
        let threeDays: TimeInterval = 3 * 24 * 3600
        var suppressed: Set<String> = []
        for annotation in annotations {
            // Only suppress if the annotation falls within the analyzed window
            let nearAny = nightDates.contains { abs($0.timeIntervalSince(annotation.eventDate)) <= threeDays }
            guard nearAny else { continue }
            for category in annotation.categories {
                if let kinds = categoryToSuppressedGenerators[category] {
                    suppressed.formUnion(kinds)
                }
            }
        }
        return suppressed
    }
}
