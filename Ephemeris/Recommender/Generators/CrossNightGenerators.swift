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
struct CalibrationAngleShiftObserver: CrossNightGenerator {
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
struct GAFreshnessObserver: CrossNightGenerator {
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
            summary = "The Guiding Assistant last ran on \(date.formatted(date: .abbreviated, time: .omitted)) — \(daysSinceGA) days ago. PHD2's Best Practices recommend running GA when seeing or equipment changes, or after long gaps; its measured min-move and backlash values supersede any computed estimate."
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

// MARK: - BaselineRegressionObserver

/// When recent nights' RMS regresses materially from the rig's established baseline,
/// surface a coaching observation pointing at the trend. Uses the rig-relative
/// threshold scheme from design doc §6.5: alert when recent median exceeds p90 or
/// 2× rig median, whichever fires first.
struct BaselineRegressionObserver: CrossNightGenerator {
    let identifier = "baselineRegressionObserver"
    init() {}

    func observe(context: CrossNightContext) -> [RecommenderObservation] {
        // Need at least 10 nights for a meaningful baseline (§6.5: "established rigs")
        guard context.nights.count >= 10,
              let baseline = context.rigBaselineMedianRMS,
              let p90 = context.rigP90RMS
        else { return [] }

        // Compute the median RMS of the most recent 3 nights (windowed signal,
        // not a single night which would be too noisy).
        let recent = context.nights.suffix(3).map { $0.medianRMSArcsec }.filter { $0 > 0 }.sorted()
        guard recent.count >= 2 else { return [] }
        let recentMedian = recent[recent.count / 2]

        // Two-tier fire: pattern when recent exceeds p90; alert when recent > 2× baseline
        let alertFloor = max(p90, baseline * 2)
        guard recentMedian >= p90 else { return [] }

        let severity: RecommenderObservation.Severity = recentMedian >= alertFloor ? .alert : .pattern

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
