import Foundation

// MARK: - CalibrationAngleShiftObserver

/// Detects step-changes in calibration orthogonality between adjacent calibrations.
/// Per design doc §9.4 (state-change inference) and validated by the corpus's
/// OAG-damage → fix → 100-pt sky-model story: a step >= 5° between two consecutive
/// calibrations is the signature of an equipment or alignment change.
///
/// When fired, the observation prompts the user to annotate the event so the engine
/// can attribute the change instead of guessing. Annotations with `category == .calibration`
/// or `.equipment` within ±3 nights of the shift suppress this generator (see
/// `AnnotationSuppression`).
nonisolated struct CalibrationAngleShiftObserver: CrossNightGenerator {
    let identifier = "calibrationAngleShiftObserver"
    init() {}

    func observe(context: CrossNightContext) -> [RecommenderObservation] {
        // Walk chronologically; flag step-changes >= 5° between adjacent calibrations.
        let calibratedNights = context.nights.compactMap { night -> (Date, Double)? in
            guard let ortho = night.calibrationOrthogonalityDeg else { return nil }
            return (night.nightDate, ortho)
        }
        guard calibratedNights.count >= 2 else { return [] }

        var results: [RecommenderObservation] = []
        for i in 1..<calibratedNights.count {
            let (priorDate, priorOrtho) = calibratedNights[i - 1]
            let (currDate, currOrtho) = calibratedNights[i]
            let delta = abs(currOrtho - priorOrtho)
            guard delta >= 5 else { continue }

            results.append(RecommenderObservation(
                scope: .crossNight,
                rigProfileId: context.profile.id,
                nightRecordIds: [],
                category: .equipment,
                severity: delta >= 10 ? .alert : .pattern,
                title: "Calibration orthogonality shifted \(String(format: "%.1f°", delta))",
                summary: "Between \(formatted(priorDate)) and \(formatted(currDate)), the calibration orthogonality changed from \(String(format: "%.1f°", priorOrtho)) to \(String(format: "%.1f°", currOrtho)). Step changes of this size typically indicate a mechanical or alignment event — the kind throughline #10 calls \"mutable and silent.\"",
                evidence: [
                    .init(label: "Prior calibration", value: "\(formatted(priorDate)) · \(String(format: "%.1f°", priorOrtho))"),
                    .init(label: "Current calibration", value: "\(formatted(currDate)) · \(String(format: "%.1f°", currOrtho))"),
                    .init(label: "Delta", value: String(format: "%.1f°", delta)),
                ],
                candidateContributors: [
                    "Equipment change (OAG, camera rotation, focuser swap, cable rerouting)",
                    "Polar-alignment refresh, mount sky model rebuild, or rebalancing",
                    "Mechanical issue developing between sessions",
                ],
                suggestedResponse: "Add an annotation for the boundary night describing what changed — the recommender will then attribute the step-change correctly and stop flagging it. If nothing changed intentionally, this is worth investigating: the Star Cross Tool can confirm mount axis response and the Calibration Assistant will produce a fresh, sanity-checked calibration.",
                relatedHelpTopicIds: [HelpTopic.calibrationOrthogonality.rawValue],
                relatedPHD2Tools: [.calibrationAssistant, .starCross, .calibrationReviewModification],
                confidence: .high,
                sourceAuthority: .ephemerisHeuristic
            ))
        }
        return results
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - GAFreshnessObserver

/// Surfaces when the Guiding Assistant hasn't run in a while. Per design doc §6.2:
/// >30 days since last GA = freshness observation.
nonisolated struct GAFreshnessObserver: CrossNightGenerator {
    let identifier = "gaFreshnessObserver"
    init() {}

    func observe(context: CrossNightContext) -> [RecommenderObservation] {
        guard !context.nights.isEmpty else { return [] }

        let mostRecentGADate = context.nights
            .filter { $0.guidingAssistantRan }
            .map { $0.nightDate }
            .max()

        let mostRecentNight = context.nights.map { $0.nightDate }.max() ?? .now

        let daysSinceGA: Int
        if let date = mostRecentGADate {
            daysSinceGA = Int(mostRecentNight.timeIntervalSince(date) / 86400)
        } else {
            // No GA found in the corpus at all
            daysSinceGA = Int(mostRecentNight.timeIntervalSince(context.nights.first?.nightDate ?? mostRecentNight) / 86400)
        }

        guard daysSinceGA >= 30 else { return [] }

        let severity: RecommenderObservation.Severity
        if mostRecentGADate == nil { severity = .pattern }
        else if daysSinceGA >= 90 { severity = .alert }
        else { severity = .coaching }

        let summary: String
        if let date = mostRecentGADate {
            summary = "The Guiding Assistant last ran on \(date.formatted(date: .abbreviated, time: .omitted)) — \(daysSinceGA) days ago. PHD2's Best Practices recommend running the GA at first setup and again as needed — after equipment changes or to re-baseline seeing; its measured min-move and backlash values supersede any computed estimate."
        } else {
            summary = "No Guiding Assistant run has been detected in your corpus. PHD2's measured values for min-move RA/Dec, exposure, and Dec backlash carry highest authority — without a GA run the recommender falls back to heuristics."
        }

        return [RecommenderObservation(
            scope: .crossNight,
            rigProfileId: context.profile.id,
            nightRecordIds: [],
            category: .phd2Hygiene,
            severity: severity,
            title: mostRecentGADate == nil ? "Guiding Assistant has never been run" : "Guiding Assistant is \(daysSinceGA) days old",
            summary: summary,
            evidence: [
                .init(label: "Last GA run", value: mostRecentGADate?.formatted(date: .abbreviated, time: .omitted) ?? "never"),
                .init(label: "Days since", value: "\(daysSinceGA)"),
                .init(label: "Threshold (coaching)", value: "30 days"),
                .init(label: "Threshold (alert)", value: "90 days"),
            ],
            candidateContributors: [],
            suggestedResponse: "Run the Guiding Assistant on your next clear night. Two-plus minutes of measurement gives you PHD2's own min-move recommendations; ten minutes adds polar-alignment error and Dec backlash. The values get written into the log and the recommender will surface them verbatim.",
            relatedHelpTopicIds: [HelpTopic.guidingAssistant.rawValue],
            relatedPHD2Tools: [.guidingAssistant],
            confidence: .high,
            sourceAuthority: .phd2Manual
        )]
    }
}

// MARK: - SubQualityDiscrepancyObserver

/// Phase 10 + throughline #9: the imaging frame is ground truth, not the guide log.
/// Fires when a night was rated `.trailed` or `.mixed` despite the guide RMS landing
/// sub-pixel — that's the classic differential-flexure signature the guide log
/// can't see on its own.
nonisolated struct SubQualityDiscrepancyObserver: CrossNightGenerator {
    let identifier = "subQualityDiscrepancyObserver"
    init() {}

    func observe(context: CrossNightContext) -> [RecommenderObservation] {
        var observations: [RecommenderObservation] = []
        for night in context.nights {
            guard let verdict = night.subQuality, verdict.isTrailedOrWorse else { continue }
            // Compute the rig-relative or imaging-scale verdict for this night's RMS.
            // The discrepancy that matters is "guide says good, image says bad".
            let rms = night.nightRMSArcsec
            let imagingScale = context.profile.imagingPixelScale
            let guidedWell: Bool
            if imagingScale > 0 {
                guidedWell = rms < imagingScale * 0.8
            } else {
                let median = context.rigBaselineMedianRMS ?? rms
                guidedWell = rms <= median
            }
            guard guidedWell else { continue }

            observations.append(RecommenderObservation(
                scope: .crossNight,
                rigProfileId: context.profile.id,
                nightRecordIds: [night.id],
                category: .subQuality,
                severity: verdict == .trailed ? .alert : .pattern,
                title: "Trailed subs despite sub-pixel guide RMS",
                summary: "On \(format(night.nightDate)), you rated the imaging frames \(verdict.displayName.lowercased()) but guide RMS was \(String(format: "%.2f″", rms)) — within or below this rig's typical baseline. The guide log can't see what the imaging frame sees; this gap is exactly what differential flexure looks like.",
                evidence: [
                    .init(label: "Date", value: format(night.nightDate)),
                    .init(label: "User rating", value: verdict.displayName),
                    .init(label: "Guide RMS", value: String(format: "%.2f″", rms)),
                    .init(label: "Imaging scale", value: imagingScale > 0 ? String(format: "%.2f″", imagingScale) : "(not configured)"),
                ],
                candidateContributors: [
                    "Differential flexure between the imaging camera and the guide camera (or OAG)",
                    "OAG prism drift relative to the imaging sensor",
                    "Camera-rotator slip or focuser sag between sessions",
                    "Mirror flop on the imaging side (SCT cassegrains specifically)",
                ],
                suggestedResponse: "Check the optical-train flexure path — the OAG-to-imager interface or, on SCT/Edge rigs, mirror lock and primary-mirror flop. PHD2's guide log can't diagnose this; the differential flexure help topic in Ephemeris walks through the typical fix path.",
                relatedHelpTopicIds: [HelpTopic.differentialFlexure.rawValue, HelpTopic.whatTheGuideLogCantTellYou.rawValue],
                relatedPHD2Tools: [],
                confidence: .high,
                sourceAuthority: .ephemerisHeuristic
            ))
        }
        return observations
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - BaselineRegressionObserver

/// When recent nights' RMS regresses materially from the rig's established baseline,
/// surface a coaching observation pointing at the trend. Uses the rig-relative
/// threshold scheme from design doc §6.5: alert when recent median exceeds p90 or
/// 2× rig median, whichever fires first.
nonisolated struct BaselineRegressionObserver: CrossNightGenerator {
    let identifier = "baselineRegressionObserver"
    init() {}

    func observe(context: CrossNightContext) -> [RecommenderObservation] {
        // Need at least 10 nights for a meaningful baseline (§6.5: "established rigs")
        guard context.nights.count >= 10 else { return [] }

        // Recent window: last 3 nights. Historical: everything else.
        // Compare recent median against HISTORICAL p90 — using the full-corpus p90 would
        // tautologically include the recent values and tie the comparison.
        let recentWindow = context.nights.suffix(3)
        let historical = context.nights.dropLast(3)
        guard recentWindow.count >= 2, historical.count >= 7 else { return [] }

        let recentSorted = recentWindow.map { $0.nightRMSArcsec }.filter { $0 > 0 }.sorted()
        guard recentSorted.count >= 2 else { return [] }
        let recentMedian = recentSorted[recentSorted.count / 2]

        let historicalSorted = historical.map { $0.nightRMSArcsec }.filter { $0 > 0 }.sorted()
        guard !historicalSorted.isEmpty else { return [] }
        let historicalMedian = historicalSorted[historicalSorted.count / 2]
        let historicalP90 = historicalSorted[Int(Double(historicalSorted.count) * 0.90)]

        // Two-tier fire: pattern when recent strictly exceeds historical p90; alert when
        // recent ≥ 2× historical median.
        let alertFloor = historicalMedian * 2
        guard recentMedian > historicalP90 else { return [] }

        let severity: RecommenderObservation.Severity = recentMedian >= alertFloor ? .alert : .pattern
        let baseline = historicalMedian
        let p90 = historicalP90

        return [RecommenderObservation(
            scope: .crossNight,
            rigProfileId: context.profile.id,
            nightRecordIds: [],
            category: .pattern,
            severity: severity,
            title: "Recent RMS above rig baseline",
            summary: "The last three nights have median RMS \(String(format: "%.2f″", recentMedian)) — beyond this rig's p90 of \(String(format: "%.2f″", p90)) computed across \(context.nights.count) nights. Per design §6.5, observations are rig-relative; this is your rig telling on itself.",
            evidence: [
                .init(label: "Recent (3-night) median", value: String(format: "%.2f″", recentMedian)),
                .init(label: "Rig baseline (median)", value: String(format: "%.2f″", baseline)),
                .init(label: "Rig p90", value: String(format: "%.2f″", p90)),
                .init(label: "Nights in baseline", value: "\(context.nights.count)"),
            ],
            candidateContributors: [
                "Atmospheric conditions (low altitude target, unstable transparency)",
                "Recent equipment change without a follow-up annotation",
                "Stale calibration relative to current sky model",
                "Optical-train degradation (dew, focus drift, dirty optics)",
            ],
            suggestedResponse: "Open the most recent log and check the document-window observations. If the elevated RMS is conditions-driven (the AtmosphericConditionsProxy observation fires alongside this one), no equipment action is needed. If not, the Guiding Assistant gives a definitive seeing measurement and PHD2's Calibration Assistant produces a fresh calibration in 5 minutes.",
            relatedHelpTopicIds: [HelpTopic.seeingVsEquipment.rawValue, HelpTopic.commonPatterns.rawValue],
            relatedPHD2Tools: [.guidingAssistant, .calibrationAssistant],
            confidence: .medium,
            sourceAuthority: .ephemerisHeuristic
        )]
    }
}
