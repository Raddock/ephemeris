import Foundation

// Nine generators implementing the data-signature → PHD2-lever rows from
// `docs/observation-gap-analysis.md` that didn't have observers yet. Each
// generator's `suggestedResponse` cites the exact PHD2 click path
// (Brain → tab → control) so the user knows what to change and where.

// MARK: - StarShapePredictionObserver

/// Surfaces the StarShapePredictor's outcome as a proper observation so it
/// appears on the document window's inspector — not just the library chip.
/// Bloated round and the two trailed sub-causes get distinct messaging.
nonisolated struct StarShapePredictionObserver: RecommenderGenerator {
    let identifier = "starShapePredictionObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        let scale = context.profile.imagingPixelScale
        guard scale > 0 else { return [] }

        // Aggregate stats across the night for the predictor's input.
        let perSession = context.sessionStats
        let totalFrames = perSession.reduce(0) { $0 + $1.stats.includedFrames }
        guard totalFrames > 0 else { return [] }
        let weightedRMS = perSession.reduce(0.0) { acc, item in
            acc + item.stats.rmsTotal * item.session.pixelScale * Double(item.stats.includedFrames)
        } / Double(totalFrames)
        let perSessionRMSArcsec = perSession.map {
            $0.stats.rmsTotal * $0.session.pixelScale
        }
        let bestRMS = perSessionRMSArcsec.min() ?? 0
        let worstRMS = perSessionRMSArcsec.max() ?? 0
        let digests = perSession.map { item -> StarShapePredictor.Input.SessionDigest in
            StarShapePredictor.Input.SessionDigest(
                rmsRAArcsec: item.stats.rmsRA * item.session.pixelScale,
                rmsDecArcsec: item.stats.rmsDec * item.session.pixelScale,
                driftRAArcsecPerMin: item.stats.driftRA * item.session.pixelScale,
                driftDecArcsecPerMin: item.stats.driftDec * item.session.pixelScale,
                includedFrames: item.stats.includedFrames
            )
        }
        let prediction = StarShapePredictor.predict(StarShapePredictor.Input(
            imagingPixelScale: scale,
            medianRMSArcsec: weightedRMS,
            bestSessionRMSArcsec: bestRMS,
            worstSessionRMSArcsec: worstRMS,
            sessions: digests
        ))

        // We only surface non-sharp predictions — sharp round is the silent default.
        let scaleRatio = weightedRMS / scale
        let title: String
        let summary: String
        let suggestedResponse: String
        let severity: RecommenderObservation.Severity
        let topics: [String]

        switch prediction {
        case .round(let bloated):
            guard bloated else { return [] }
            title = "Stars predicted: round but bloated"
            summary = "RMS \(formatArcsec(weightedRMS)) is \(formatRatio(scaleRatio))× your imaging scale \(formatArcsec(scale)). Guiding is symmetric so stars stay round, but they're imaged wider than the sensor can resolve — they'll look soft."
            suggestedResponse = "There's no PHD2 lever for this — bloated round usually means the mount is at its capacity for the imaging scale you're chasing. Two paths: accept the soft floor (long focal length mounts often live here), or reduce the imaging scale with a focal reducer or 2× binning so the guide RMS fits inside one pixel."
            severity = .coaching
            topics = [HelpTopic.imageScaleRatio.rawValue, HelpTopic.opticalTrainHealth.rawValue]

        case .slightlyElongated:
            title = "Stars predicted: slightly elongated"
            summary = "Axis-asymmetric RMS — one axis is meaningfully larger than the other, producing egg-shaped stars. The corrective lever depends on which axis is worse; PHD2's Brain dialog tunes them independently."
            suggestedResponse = "Brain → Algorithms tab: raise the **Aggressiveness** on whichever axis is lagging, or lower **Minimum move** so smaller motions get corrected. Run Tools → **Guiding Assistant** for PHD2's own per-axis recommendations."
            severity = .pattern
            topics = [HelpTopic.aggressivenessAndMinMove.rawValue, HelpTopic.guidingAssistant.rawValue]

        case .trailed(let cause):
            switch cause {
            case .decDrift:
                title = "Stars predicted: trailed (Dec drift)"
                summary = "Dec axis dominated the drift across the night — that's the canonical polar-alignment-error fingerprint. Drift over a typical sub exposure exceeds your imaging scale."
                suggestedResponse = "Tools → **Drift Alignment**, **Static Polar Alignment**, or **Polar Drift Alignment** — pick whichever fits your routine. The Guiding Assistant also reports polar-alignment error directly if you'd like a measurement first."
                topics = [HelpTopic.polarAlignmentFundamentals.rawValue, HelpTopic.guidingAssistant.rawValue]
            case .raDrift:
                title = "Stars predicted: trailed (RA drift)"
                summary = "RA axis dominated the drift. Usual suspects are periodic error overwhelming corrections, wind shake at the OTA, or a tracking-rate mismatch (custom rate, refraction model)."
                suggestedResponse = "Brain → Mount tab: verify **RA guide rate** matches what your mount actually drives at. If your mount supports PE training, train it. If wind, shield the OTA. Brain → Algorithms → consider **PredictivePEC** if the drift is periodic."
                topics = [HelpTopic.commonPatterns.rawValue, HelpTopic.guideAlgorithms.rawValue]
            case .bothAxes:
                title = "Stars predicted: trailed (both axes)"
                summary = "Both RA and Dec drifted. Rarer — usually the mount lost tracking or its pointing model is unstable. Tracking failure mid-session, refraction model misconfigured, or guide-rate severely wrong are the typical causes."
                suggestedResponse = "Verify the mount is actually tracking sidereal (or your chosen custom rate). Recalibrate via Tools → **Calibration Assistant**. If you use a pointing model, rebuild it. Brain → Mount tab → check **RA / Dec guide rate**."
                topics = [HelpTopic.calibrationTroubleshooting.rawValue]
            }
            severity = .pattern

        case .mixed:
            title = "Sessions disagreed across the night"
            summary = "The best-to-worst session RMS spread within this night exceeded 3×. Conditions or equipment state changed substantially mid-night — the user's eye will see some good subs and some bad ones."
            suggestedResponse = "Not a PHD2-tunable issue. Common causes: a passing cloud bank, wind picking up, a meridian flip without a recalibration, or dew/cooldown changing mid-session. Add an annotation (📝 button on the night row) if you noticed something — the cross-night recommender uses annotations to attribute step-changes."
            severity = .coaching
            topics = [HelpTopic.seeingVsEquipment.rawValue, HelpTopic.commonPatterns.rawValue]

        case .unknown:
            return []
        }

        return [RecommenderObservation(
            scope: .singleNight,
            rigProfileId: context.profile.id,
            nightRecordIds: [],
            category: .pattern,
            severity: severity,
            title: title,
            summary: summary,
            evidence: [
                .init(label: "Predicted shape", value: prediction.displayName),
                .init(label: "Median RMS", value: formatArcsec(weightedRMS)),
                .init(label: "Imaging scale", value: formatArcsec(scale)),
                .init(label: "Scale ratio", value: String(format: "%.2f×", scaleRatio)),
            ],
            candidateContributors: [],
            suggestedResponse: suggestedResponse,
            relatedHelpTopicIds: topics,
            relatedPHD2Tools: prediction.isBloated ? [] : [.guidingAssistant],
            confidence: .medium,
            sourceAuthority: .ephemerisHeuristic
        )]
    }
}

// MARK: - PierSideBiasObserver

/// PHD2 calibration is pier-side dependent. If Dec polarity skew or RMS differs
/// markedly between west and east pier sessions in the same night, the cal data
/// is likely stale on one side (or the sky model / refraction is asymmetric).
/// We only fire when both pier sides are represented in the night.
nonisolated struct PierSideBiasObserver: RecommenderGenerator {
    let identifier = "pierSideBiasObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        var westSessions: [SessionStats] = []
        var eastSessions: [SessionStats] = []
        for (session, stats) in context.sessionStats {
            switch session.headerProperties.pierSide?.lowercased() {
            case "west": westSessions.append(stats)
            case "east": eastSessions.append(stats)
            default: continue
            }
        }
        guard !westSessions.isEmpty, !eastSessions.isEmpty else { return [] }

        let pixelScale = context.sessionStats.first?.session.pixelScale ?? 1.0
        let westRMS = mean(westSessions.map { $0.rmsTotal * pixelScale })
        let eastRMS = mean(eastSessions.map { $0.rmsTotal * pixelScale })
        let westDecDrift = mean(westSessions.map { abs($0.driftDec) * pixelScale })
        let eastDecDrift = mean(eastSessions.map { abs($0.driftDec) * pixelScale })
        guard westRMS > 0, eastRMS > 0 else { return [] }

        // Two firing conditions:
        // 1. RMS differs by > 50% between pier sides — strong asymmetry signature
        // 2. Dec drift differs by > 0.05″/min between sides — calibration-orientation bug
        let rmsRatio = max(westRMS, eastRMS) / min(westRMS, eastRMS)
        let decDriftDelta = abs(westDecDrift - eastDecDrift)

        guard rmsRatio > 1.5 || decDriftDelta > 0.05 else { return [] }

        let worseSide = westRMS > eastRMS ? "west" : "east"
        return [RecommenderObservation(
            scope: .singleNight,
            rigProfileId: context.profile.id,
            nightRecordIds: [],
            category: .pattern,
            severity: .pattern,
            title: "Pier-side asymmetry detected",
            summary: "The \(worseSide) pier side ran noticeably differently from the other this night (RMS ratio \(formatRatio(rmsRatio))×). PHD2 calibration is pier-side dependent — the underlying cause is usually a calibration that's stale or wrong on one side.",
            evidence: [
                .init(label: "West RMS", value: formatArcsec(westRMS)),
                .init(label: "East RMS", value: formatArcsec(eastRMS)),
                .init(label: "West Dec drift", value: String(format: "%.3f″/min", westDecDrift)),
                .init(label: "East Dec drift", value: String(format: "%.3f″/min", eastDecDrift)),
            ],
            candidateContributors: [
                "Calibration only refreshed on one side after a recent equipment change",
                "Auto-reverse-Dec setting misconfigured for the mount",
                "Refraction model behaving asymmetrically near the meridian",
            ],
            suggestedResponse: "Tools → **Calibration Review and Modification** — confirm a fresh calibration exists for the \(worseSide) pier side. If not, recalibrate there. Brain → Mount → verify **Reverse Dec output after meridian flip** matches your mount's behavior.",
            relatedHelpTopicIds: [HelpTopic.calibrationTroubleshooting.rawValue, HelpTopic.calibrationOrthogonality.rawValue],
            relatedPHD2Tools: [.calibrationReviewModification, .calibrationAssistant],
            confidence: .medium,
            sourceAuthority: .ephemerisHeuristic
        )]
    }

    private func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - CooldownSignatureObserver

/// First-hour-of-night elevated RMS: the classic SCT / large-OTA cooldown signature.
/// If the first session(s) ran noticeably worse than the rest of the night's median,
/// thermal equilibration is the most parsimonious explanation.
nonisolated struct CooldownSignatureObserver: RecommenderGenerator {
    let identifier = "cooldownSignatureObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        let sessions = context.sessionStats.sorted { (a, b) in
            (a.session.startedAt ?? .distantPast) < (b.session.startedAt ?? .distantPast)
        }
        guard sessions.count >= 3 else { return [] }   // need a baseline of "later in the night"

        let pixelScale = sessions[0].session.pixelScale
        let firstRMS = sessions[0].stats.rmsTotal * pixelScale
        // Median across sessions 2..end, ignoring the first.
        let laterRMS = sessions.dropFirst().map { $0.stats.rmsTotal * pixelScale }.sorted()
        let laterMedian = laterRMS[laterRMS.count / 2]

        guard firstRMS > 0, laterMedian > 0 else { return [] }
        let ratio = firstRMS / laterMedian
        guard ratio >= 1.5 else { return [] }   // first session ≥ 1.5× the later median

        return [RecommenderObservation(
            scope: .singleNight,
            rigProfileId: context.profile.id,
            nightRecordIds: [],
            category: .pattern,
            severity: .coaching,
            title: "First session ran \(formatRatio(ratio))× worse than later sessions",
            summary: "RMS \(formatArcsec(firstRMS)) on the first session of the night, vs a median of \(formatArcsec(laterMedian)) across the rest. That's the classic cooldown signature — OTA thermal mass radiating heat until tube currents settle.",
            evidence: [
                .init(label: "First session RMS", value: formatArcsec(firstRMS)),
                .init(label: "Later sessions median", value: formatArcsec(laterMedian)),
                .init(label: "Ratio", value: String(format: "%.2f×", ratio)),
            ],
            candidateContributors: [
                "OTA still cooling — tube currents and seeing-inside-tube",
                "Focuser temperature drift during the first hour",
                "Mount mechanical settling after slew",
                "Dew or transparency change as the night progressed",
            ],
            suggestedResponse: "Not a PHD2 lever. If you can, start uncovering the OTA earlier so it hits ambient temperature before imaging. A low-speed fan on Schmidt-Cassegrains and a corrector dew heater shorten the cooldown window measurably. Treat first-session subs as discardable if image quality matters.",
            relatedHelpTopicIds: [HelpTopic.opticalTrainHealth.rawValue, HelpTopic.preFlightChecklist.rawValue],
            relatedPHD2Tools: [],
            confidence: .medium,
            sourceAuthority: .ephemerisHeuristic
        )]
    }
}

// MARK: - MinMoveValidationObserver

/// Compares the active min-move (from header) against the seeing floor implied by
/// the data. Without a GA run we estimate the floor from the median absolute
/// deviation of pre-algorithm raw distances on the "quiet half" of the session.
nonisolated struct MinMoveValidationObserver: RecommenderGenerator {
    let identifier = "minMoveValidationObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        // Aggregate raw distances across every session in the night and emit at
        // most one observation per axis, so a multi-session night doesn't stack
        // duplicate cards. The active min-move is taken from the most-recent
        // session whose header carries the value.
        var allRA: [Double] = []
        var allDec: [Double] = []
        var lastActiveRA: Double?
        var lastActiveDec: Double?
        for (session, _) in context.sessionStats {
            let included = session.entries.filter { $0.included }
            guard included.count >= 50 else { continue }
            allRA.append(contentsOf: included.map { abs($0.raRawDistance) })
            allDec.append(contentsOf: included.map { abs($0.decRawDistance) })
            let props = session.headerProperties
            if let v = props.raMinMovePixels  { lastActiveRA  = v }
            if let v = props.decMinMovePixels { lastActiveDec = v }
        }
        guard allRA.count >= 100 else { return [] }
        let sortedRA = allRA.sorted()
        let sortedDec = allDec.sorted()
        let raFloor = median(of: Array(sortedRA.prefix(sortedRA.count / 2)))
        let decFloor = median(of: Array(sortedDec.prefix(sortedDec.count / 2)))

        var observations: [RecommenderObservation] = []
        if let active = lastActiveRA, raFloor > 0,
           let obs = mismatchObservation(axis: "RA", activePx: active, floorPx: raFloor, rigProfileId: context.profile.id) {
            observations.append(obs)
        }
        if let active = lastActiveDec, decFloor > 0,
           let obs = mismatchObservation(axis: "Dec", activePx: active, floorPx: decFloor, rigProfileId: context.profile.id) {
            observations.append(obs)
        }
        return observations
    }

    private func mismatchObservation(axis: String,
                                     activePx: Double,
                                     floorPx: Double,
                                     rigProfileId: UUID) -> RecommenderObservation? {
        let ratio = activePx / floorPx
        // Sane band: 0.8–1.5× the seeing floor. Outside that, flag.
        guard ratio < 0.8 || ratio > 1.5 else { return nil }
        let title: String
        let summary: String
        let suggestedResponse: String
        if ratio > 1.5 {
            title = "\(axis) min-move likely too high — missing real motion"
            summary = "Your active \(axis) min-move of \(formatPx(activePx)) is \(formatRatio(ratio))× the seeing floor estimated from this session's pre-algorithm distances. PHD2 will be ignoring real corrections that fall below the threshold."
            suggestedResponse = "Run Tools → **Guiding Assistant** — it measures the optimum min-move directly. Or in Brain → Algorithms → \(axis) → **Minimum move**, drop the value to roughly \(formatPx(floorPx))."
        } else {
            title = "\(axis) min-move likely too low — chasing seeing"
            summary = "Your active \(axis) min-move of \(formatPx(activePx)) is below the seeing floor (\(formatPx(floorPx)) estimated). PHD2 will be issuing corrections for atmospheric jitter, which can amplify noise instead of dampening it."
            suggestedResponse = "Run Tools → **Guiding Assistant**, or in Brain → Algorithms → \(axis) → **Minimum move**, raise the value to roughly \(formatPx(floorPx))."
        }
        return RecommenderObservation(
            scope: .singleNight,
            rigProfileId: rigProfileId,
            nightRecordIds: [],
            category: .pattern,
            severity: .pattern,
            title: title,
            summary: summary,
            evidence: [
                .init(label: "Active \(axis) min-move", value: formatPx(activePx)),
                .init(label: "Estimated seeing floor", value: formatPx(floorPx)),
                .init(label: "Ratio", value: String(format: "%.2f×", ratio)),
            ],
            candidateContributors: [],
            suggestedResponse: suggestedResponse,
            relatedHelpTopicIds: [HelpTopic.aggressivenessAndMinMove.rawValue, HelpTopic.guidingAssistant.rawValue],
            relatedPHD2Tools: [.guidingAssistant],
            confidence: .medium,
            sourceAuthority: .ephemerisHeuristic
        )
    }

    private func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values[values.count / 2]
    }
}

// MARK: - GuideRateValidationObserver

/// Compares the header's reported guide rate against motion observed per pulse.
/// expected_motion_px = pulse_ms * guide_rate_arcsec_per_sec / pixelScale / 1000.
/// We check the ratio of summed observed-to-expected motion across the session;
/// > 30% deviation suggests the rate is misconfigured or backlash is eating pulses.
nonisolated struct GuideRateValidationObserver: RecommenderGenerator {
    let identifier = "guideRateValidationObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        // Aggregate across all sessions: sum expected vs observed across the night,
        // emit at most one observation. Dedupes multi-session nights.
        var sumExpected = 0.0
        var sumObserved = 0.0
        var raRateForNote: Double?
        for (session, _) in context.sessionStats {
            let props = session.headerProperties
            guard let raRate = props.raGuideSpeedArcsecPerSec else { continue }
            raRateForNote = raRate
            let pxScale = session.pixelScale
            guard pxScale > 0 else { continue }
            for entry in session.entries where entry.included {
                let pulseMs = abs(Double(entry.raDuration))
                guard pulseMs > 10 else { continue }
                let expectedPx = (pulseMs * raRate / 1000.0) / pxScale
                let observedPx = abs(entry.raRawDistance)
                sumExpected += expectedPx
                sumObserved += observedPx
            }
        }
        guard sumExpected > 20, let raRate = raRateForNote else { return [] }
        let ratio = sumObserved / sumExpected
        guard ratio < 0.7 || ratio > 1.4 else { return [] }

        let direction = ratio < 0.7 ? "less" : "more"
        let suspect = ratio < 0.7
            ? "Backlash eating pulses, or RA guide rate set too high in PHD2 vs what the mount actually drives"
            : "PHD2's RA guide rate is too low — corrections aren't accounting for the mount's true response"
        return [RecommenderObservation(
                scope: .singleNight,
                rigProfileId: context.profile.id,
                nightRecordIds: [],
                category: .pattern,
                severity: .pattern,
                title: "RA guide rate may be misconfigured",
                summary: "RA corrections are producing \(direction) motion than the reported guide rate predicts (observed/expected ratio \(formatRatio(ratio))×). Either the rate value in PHD2 is wrong or something is absorbing pulses.",
                evidence: [
                    .init(label: "Reported RA guide rate", value: String(format: "%.3f a-s/s", raRate)),
                    .init(label: "Observed/expected motion ratio", value: String(format: "%.2f×", ratio)),
                ],
                candidateContributors: [
                    "Brain → Mount → RA guide rate doesn't match the mount's actual rate",
                    "RA backlash or stiction absorbing pulse motion",
                    "Mount driver reporting a stale rate to PHD2",
                ],
                suggestedResponse: "Brain → Mount tab → check **RA guide rate**. If your mount uses a software guide rate (typically 0.5× sidereal), set it explicitly. If the value matches the mount but observed motion still disagrees, the most likely culprit is backlash — try Tools → **Guiding Assistant** for a fresh measurement, or recalibrate via Tools → **Calibration Assistant**. \(suspect).",
                relatedHelpTopicIds: [HelpTopic.calibrationTroubleshooting.rawValue, HelpTopic.guidingAssistant.rawValue],
            relatedPHD2Tools: [.guidingAssistant, .calibrationAssistant],
            confidence: .low,
            sourceAuthority: .ephemerisHeuristic
        )]
    }
}

// MARK: - AggressivenessObserver

/// Lag-1 autocorrelation of post-algorithm guide-corrected distances per axis.
/// Strongly negative (< -0.3) = oscillation → aggressiveness too high.
/// Strongly positive (> 0.3) with persistent drift = sluggish → too low.
nonisolated struct AggressivenessObserver: RecommenderGenerator {
    let identifier = "aggressivenessObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        // Concatenate guide-corrected distances across every session (with NaN
        // gaps between sessions so lag-1 doesn't bridge them), then compute one
        // autocorrelation per axis. Emit at most one observation per axis per
        // night, so a 12-session night doesn't stack 12 identical cards.
        var raValues: [Double] = []
        var decValues: [Double] = []
        var raRMSWeighted = 0.0
        var decRMSWeighted = 0.0
        var totalFrames = 0
        var lastActiveRAAggro: Double?
        var lastActiveDecAggro: Double?
        var sessionCount = 0
        for (session, stats) in context.sessionStats {
            let included = session.entries.filter { $0.included }
            guard included.count >= 100 else { continue }
            sessionCount += 1
            if !raValues.isEmpty { raValues.append(.nan) }  // boundary separator
            if !decValues.isEmpty { decValues.append(.nan) }
            raValues.append(contentsOf: included.map { $0.raGuideDistance })
            decValues.append(contentsOf: included.map { $0.decGuideDistance })
            let frames = included.count
            totalFrames += frames
            raRMSWeighted += stats.rmsRA * session.pixelScale * Double(frames)
            decRMSWeighted += stats.rmsDec * session.pixelScale * Double(frames)
            let props = session.headerProperties
            if let v = props.raAggressivenessPercent  { lastActiveRAAggro  = v }
            if let v = props.decAggressivenessPercent { lastActiveDecAggro = v }
        }
        guard totalFrames > 0, sessionCount > 0 else { return [] }
        let raRMS = raRMSWeighted / Double(totalFrames)
        let decRMS = decRMSWeighted / Double(totalFrames)

        var observations: [RecommenderObservation] = []
        if let acRA = lagOneAutocorrelation(values: raValues),
           let obs = makeObservation(axis: "RA", autocorr: acRA,
                                     activeAggression: lastActiveRAAggro,
                                     rmsAxisArcsec: raRMS,
                                     rigProfileId: context.profile.id) {
            observations.append(obs)
        }
        if let acDec = lagOneAutocorrelation(values: decValues),
           let obs = makeObservation(axis: "Dec", autocorr: acDec,
                                     activeAggression: lastActiveDecAggro,
                                     rmsAxisArcsec: decRMS,
                                     rigProfileId: context.profile.id) {
            observations.append(obs)
        }
        return observations
    }

    private func makeObservation(axis: String,
                                 autocorr: Double,
                                 activeAggression: Double?,
                                 rmsAxisArcsec: Double,
                                 rigProfileId: UUID) -> RecommenderObservation? {
        // Only fire on clear signals — autocorr threshold ±0.3.
        guard abs(autocorr) > 0.3 else { return nil }
        let title: String
        let summary: String
        let suggestedResponse: String
        if autocorr < -0.3 {
            title = "\(axis) corrections appear to be oscillating"
            summary = "Lag-1 autocorrelation of \(axis) corrections is \(String(format: "%.2f", autocorr)). Strongly negative autocorrelation means every correction tends to reverse the previous one — PHD2 is overshooting and chasing back."
            if let aggro = activeAggression {
                let target = max(10, aggro - 15)
                suggestedResponse = "Brain → Algorithms → \(axis) → **Aggressiveness** is currently \(Int(aggro))%. Try dropping it to about \(Int(target))%. If the algorithm is **ResistSwitch**, consider **Hysteresis** or **LowPass2** for a less reactive response."
            } else {
                suggestedResponse = "Brain → Algorithms → \(axis) → lower **Aggressiveness** by 10–20 percentage points. If still oscillating, switch the algorithm to **Hysteresis** or **LowPass2**."
            }
        } else {
            title = "\(axis) corrections appear sluggish"
            summary = "Lag-1 autocorrelation of \(axis) corrections is \(String(format: "+%.2f", autocorr)). Strongly positive autocorrelation means errors persist frame-to-frame — PHD2 isn't responding aggressively enough to keep up."
            if let aggro = activeAggression {
                let target = min(95, aggro + 15)
                suggestedResponse = "Brain → Algorithms → \(axis) → **Aggressiveness** is currently \(Int(aggro))%. Try raising it to about \(Int(target))%."
            } else {
                suggestedResponse = "Brain → Algorithms → \(axis) → raise **Aggressiveness** by 10–20 percentage points."
            }
        }
        var evidence: [EvidenceItem] = [
            .init(label: "\(axis) lag-1 autocorr", value: String(format: "%+.2f", autocorr)),
            .init(label: "\(axis) RMS", value: formatArcsec(rmsAxisArcsec)),
        ]
        if let aggro = activeAggression {
            evidence.append(.init(label: "Active \(axis) aggressiveness", value: "\(Int(aggro))%"))
        }
        return RecommenderObservation(
            scope: .singleNight,
            rigProfileId: rigProfileId,
            nightRecordIds: [],
            category: .pattern,
            severity: .pattern,
            title: title,
            summary: summary,
            evidence: evidence,
            candidateContributors: [],
            suggestedResponse: suggestedResponse,
            relatedHelpTopicIds: [HelpTopic.aggressivenessAndMinMove.rawValue, HelpTopic.guideAlgorithms.rawValue],
            relatedPHD2Tools: [.guidingAssistant],
            confidence: .medium,
            sourceAuthority: .ephemerisHeuristic
        )
    }

    /// Pearson lag-1 autocorrelation. NaN values act as session-boundary breaks
    /// (we don't bridge across them, so the autocorr doesn't conflate end-of-session-N
    /// with start-of-session-N+1). Returns nil if too few valid pairs remain.
    private func lagOneAutocorrelation(values: [Double]) -> Double? {
        let finite = values.filter { !$0.isNaN }
        guard finite.count >= 50 else { return nil }
        let mean = finite.reduce(0, +) / Double(finite.count)
        var num = 0.0
        var pairs = 0
        for i in 0..<(values.count - 1) {
            let a = values[i], b = values[i + 1]
            guard !a.isNaN, !b.isNaN else { continue }
            num += (a - mean) * (b - mean)
            pairs += 1
        }
        guard pairs >= 30 else { return nil }
        var den = 0.0
        for v in finite { den += (v - mean) * (v - mean) }
        guard den > 0 else { return nil }
        return num / den
    }
}

// MARK: - DataDrivenAlgorithmHintObserver

/// Looks for a sinusoidal residual at a likely worm period in the RA axis.
/// If found, suggests PredictivePEC. (LowPass2 hint is folded into the
/// existing AlgorithmMismatch observer.)
nonisolated struct DataDrivenAlgorithmHintObserver: RecommenderGenerator {
    let identifier = "dataDrivenAlgorithmHintObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        // Find the longest session in the night (most reliable FFT) and analyze
        // its RA spectrum only. If a worm-period peak is present there, fire one
        // observation — no need to repeat per-session for what is fundamentally a
        // mount-level signature.
        guard let longest = context.sessionStats.max(by: {
            $0.session.entries.count < $1.session.entries.count
        }) else { return [] }
        let session = longest.session
        let props = session.headerProperties
        if props.raGuideAlgorithm?.lowercased().contains("predictive") == true { return [] }

        guard let spectrum = FrequencyAnalyzer.analyze(
            session: session,
            axis: .ra,
            driftCorrect: true
        ) else { return [] }
        guard let dominant = spectrum.dominantPeriod else { return [] }
        guard dominant >= 200, dominant <= 600 else { return [] }

        return [RecommenderObservation(
                scope: .singleNight,
                rigProfileId: context.profile.id,
                nightRecordIds: [],
                category: .pattern,
                severity: .suggestion,
                title: "Periodic residual detected at ~\(Int(dominant))s — try PredictivePEC",
                summary: "FFT of the RA axis after drift removal shows a strong peak around \(Int(dominant)) seconds. That's consistent with mount worm period and the kind of signal PHD2's PredictivePEC algorithm is designed to anticipate.",
                evidence: [
                    .init(label: "Dominant RA period", value: "\(Int(dominant))s"),
                    .init(label: "Current RA algorithm", value: props.raGuideAlgorithm ?? "unknown"),
                ],
                candidateContributors: [
                    "Mount periodic error within the worm period range",
                    "Belt-drive harmonic on some friction-drive mounts",
                ],
                suggestedResponse: "Brain → Algorithms → RA tab → switch the **algorithm** to **PredictivePEC**. PredictivePEC learns the mount's periodic residual and applies forward-looking corrections rather than reacting to it. Several sessions of training data are required for it to be useful.",
            relatedHelpTopicIds: [HelpTopic.guideAlgorithms.rawValue, HelpTopic.commonPatterns.rawValue],
            relatedPHD2Tools: [.guidingAssistant],
            confidence: .low,
            sourceAuthority: .ephemerisHeuristic
        )]
    }
}

// MARK: - GuideScaleMismatchObserver

/// Cross-checks the rig profile's stored guide-train values against the values
/// PHD2 actually reported in the log header, and flags when the resulting guide
/// pixel scale is outside 0.5–1.5× of the imaging scale.
nonisolated struct GuideScaleMismatchObserver: RecommenderGenerator {
    let identifier = "guideScaleMismatchObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        var observations: [RecommenderObservation] = []
        let profile = context.profile
        let imagingScale = profile.imagingPixelScale
        guard let session = context.sessions.first else { return [] }
        let headerScale = session.pixelScale  // PHD2-reported guide arcsec/px

        // 1. Profile-vs-header mismatch: the rig profile says guide focal length X
        //    and pixel Y, the PHD2 header reports a different effective scale.
        if profile.guideFocalLength > 0 && profile.guideCameraPixelSize > 0 {
            let profileGuideScale = ImagingScale.compute(
                focalLengthMm: profile.guideFocalLength,
                pixelSizeMicrons: profile.guideCameraPixelSize,
                binning: profile.guideBinning,
                reducerFactor: nil
            )
            if profileGuideScale > 0 && headerScale > 0 {
                let ratio = max(profileGuideScale, headerScale) / min(profileGuideScale, headerScale)
                if ratio > 1.10 {
                    observations.append(RecommenderObservation(
                        scope: .singleNight,
                        rigProfileId: profile.id,
                        nightRecordIds: [],
                        category: .opticalTrain,
                        severity: .equipment,
                        title: "Rig profile and PHD2 disagree about the guide scale",
                        summary: "Your rig profile computes \(formatArcsec(profileGuideScale))/px from its stored guide focal length \(Int(profile.guideFocalLength))mm × pixel \(formatPxSize(profile.guideCameraPixelSize)) × bin \(profile.guideBinning). PHD2's session header reports \(formatArcsec(headerScale))/px. Recommendations that depend on the guide scale will be computed against whichever number is wrong.",
                        evidence: [
                            .init(label: "Rig profile scale", value: "\(formatArcsec(profileGuideScale))/px"),
                            .init(label: "PHD2 header scale", value: "\(formatArcsec(headerScale))/px"),
                            .init(label: "Ratio", value: String(format: "%.2f×", ratio)),
                        ],
                        candidateContributors: [
                            "Rig profile values weren't updated after a guide-train change",
                            "Binning set differently in PHD2 than what the profile records",
                        ],
                        suggestedResponse: "Open App → Rig Profiles… and update the guide focal length / pixel size / binning to match what PHD2 reports in the log header (\(formatArcsec(headerScale))/px).",
                        relatedHelpTopicIds: [HelpTopic.pixelScaleAndResolution.rawValue],
                        relatedPHD2Tools: [],
                        confidence: .high,
                        sourceAuthority: .ephemerisHeuristic
                    ))
                }
            }
        }

        // 2. Guide-to-imaging scale ratio outside the design's 0.5–1.5× band.
        if imagingScale > 0 && headerScale > 0 {
            let guideToImaging = headerScale / imagingScale
            if guideToImaging < 0.5 || guideToImaging > 1.5 {
                let direction = guideToImaging < 0.5
                    ? "oversampled — the guider is seeing more detail than the imager, which makes it chase seeing"
                    : "undersampled — the guider can't see motion small enough to matter for your imaging scale"
                observations.append(RecommenderObservation(
                    scope: .singleNight,
                    rigProfileId: profile.id,
                    nightRecordIds: [],
                    category: .opticalTrain,
                    severity: .coaching,
                    title: "Guide scale far from imaging scale",
                    summary: "Guide pixel scale is \(formatArcsec(headerScale))/px and imaging pixel scale is \(formatArcsec(imagingScale))/px (\(formatRatio(guideToImaging))×). That's \(direction).",
                    evidence: [
                        .init(label: "Guide pixel scale", value: "\(formatArcsec(headerScale))/px"),
                        .init(label: "Imaging pixel scale", value: "\(formatArcsec(imagingScale))/px"),
                        .init(label: "Guide/Imaging ratio", value: String(format: "%.2f×", guideToImaging)),
                    ],
                    candidateContributors: [],
                    suggestedResponse: "Not a PHD2 tuning issue — this is a hardware-train mismatch. A guide camera with different pixel pitch, a different guide-scope focal length, or guide-camera binning would shift the ratio. PHD2 manual recommends a guide scale in the 0.5–1.5× range of the imaging scale for the best signal-to-noise on the corrections.",
                    relatedHelpTopicIds: [HelpTopic.pixelScaleAndResolution.rawValue, HelpTopic.imageScaleRatio.rawValue],
                    relatedPHD2Tools: [],
                    confidence: .medium,
                    sourceAuthority: .ephemerisHeuristic
                ))
            }
        }

        return observations
    }
}

// MARK: - StarLostObserver

/// Counts star-lost events and fires when more than ~5% of the session's frames
/// reported "star lost" through INFO entries or via the parser-flagged errorCode.
nonisolated struct StarLostObserver: RecommenderGenerator {
    let identifier = "starLostObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        // Aggregate across the night so a multi-session night yields at most one
        // observation, with the rate computed off the whole-night frame totals.
        var totalFrames = 0
        var totalLost = 0
        for session in context.sessions {
            totalFrames += session.entries.count
            totalLost += session.entries.filter { $0.errorCode > 1 }.count
        }
        guard totalFrames >= 200 else { return [] }
        let lostRatio = Double(totalLost) / Double(totalFrames)
        guard lostRatio > 0.05 else { return [] }

        return [RecommenderObservation(
                scope: .singleNight,
                rigProfileId: context.profile.id,
                nightRecordIds: [],
                category: .equipment,
                severity: .pattern,
                title: "Star lost on \(Int(lostRatio * 100))% of frames",
                summary: "\(totalLost) of \(totalFrames) frames across the night reported a guide-star error. That's high enough to interrupt the guide loop repeatedly and prevent the corrections feedback from settling.",
                evidence: [
                    .init(label: "Frames lost", value: "\(totalLost) / \(totalFrames)"),
                    .init(label: "Lost ratio", value: String(format: "%.1f%%", lostRatio * 100)),
                ],
                candidateContributors: [
                    "Guide star drifting out of the search region (focus or scale issue)",
                    "Star mass tolerance too tight — variable transparency clips the star",
                    "Thin clouds or dew on the corrector",
                    "Search region cropped to a too-small subframe",
                ],
                suggestedResponse: "Brain → Guiding tab → widen **Search region** (typical default 15px; try 25–30px). Brain → Guiding → relax **Star mass tolerance** if you've tightened it. Brain → Camera → check the **no-star timeout**. If transparency is the cause, consider running multi-star (Brain → Guiding → **Use multi-star guiding**).",
                relatedHelpTopicIds: [HelpTopic.multiStarGuiding.rawValue, HelpTopic.opticalTrainHealth.rawValue],
                relatedPHD2Tools: [.autoSelectStars],
                confidence: .high,
                sourceAuthority: .ephemerisHeuristic
            )]
    }
}

// MARK: - Shared formatters

private nonisolated func formatArcsec(_ v: Double) -> String { String(format: "%.2f″", v) }
private nonisolated func formatRatio(_ v: Double) -> String { String(format: "%.2f", v) }
private nonisolated func formatPx(_ v: Double) -> String { String(format: "%.2f px", v) }
private nonisolated func formatPxSize(_ v: Double) -> String { String(format: "%.2fµm", v) }
