import Foundation

// MARK: - GuidingAssistantRecommendationObserver

/// Surfaces PHD2 Guiding Assistant recommendations verbatim from the log.
/// This is the highest-authority generator — its observations supersede any parallel
/// Ephemeris computation per design doc §6.2 and throughline #4 secondary clause.
nonisolated struct GuidingAssistantRecommendationObserver: RecommenderGenerator {
    let identifier = "guidingAssistantRecommendationObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        // GAResultParser owns the real "INFO: GA Result - …" line format — the same
        // parse the ingestor persists, so the observation and the GAResultEntity can
        // never disagree about what PHD2 measured.
        var observations: [RecommenderObservation] = []
        for session in context.sessions {
            for parsed in GAResultParser.parse(session: session) {
                guard let observation = buildObservation(result: parsed,
                                                         rigProfileId: context.profile.id,
                                                         sessionStartedAt: session.startedAt) else { continue }
                observations.append(observation)
            }
        }
        return observations
    }

    private func buildObservation(result: GAResultParser.Parsed,
                                  rigProfileId: UUID,
                                  sessionStartedAt: Date?) -> RecommenderObservation? {
        guard result.hasRecommendations else { return nil }

        var evidence: [EvidenceItem] = []
        if let v = result.highFreqStarMotionArcsecRMS {
            evidence.append(.init(label: "High-frequency star motion (HPF-RMS)", value: String(format: "%.2f″", v),
                                  detail: "Seeing-driven motion guiding can't correct — the floor for min-move"))
        }
        if let v = result.raPeakToPeakArcsec    { evidence.append(.init(label: "RA peak-to-peak", value: String(format: "%.2f″", v))) }
        if let v = result.raMaxRateOfChangeArcsecPerSec { evidence.append(.init(label: "Max RA drift rate", value: String(format: "%.2f″/s", v))) }
        if let v = result.recommendedRAMinMovePx  { evidence.append(.init(label: "Suggested RA min-move", value: String(format: "%.2f px", v))) }
        if let v = result.recommendedDecMinMovePx { evidence.append(.init(label: "Suggested Dec min-move", value: String(format: "%.2f px", v))) }
        if let v = result.recommendedExposureSec  { evidence.append(.init(label: "Drift-limiting exposure", value: String(format: "%.1f s", v))) }
        if let v = result.polarAlignErrorArcmin   { evidence.append(.init(label: "Polar alignment error", value: String(format: "%.1f′", v))) }
        if let v = result.decBacklashMs {
            let assessment: String
            if v < 100 { assessment = "negligible (no compensation needed)" }
            else if v < 3000 { assessment = "use backlash compensation" }
            else { assessment = "exceeds 3 s — use uni-directional Dec guiding" }
            evidence.append(.init(label: "Dec backlash", value: String(format: "%.0f ms", v), detail: assessment))
        }

        return RecommenderObservation(
            scope: .singleNight,
            rigProfileId: rigProfileId,
            nightRecordIds: [],
            sessionStartedAt: sessionStartedAt,
            category: .phd2Hygiene,
            severity: .hygiene,
            title: "Guiding Assistant ran during this session",
            summary: "PHD2's Guiding Assistant measured your rig directly. The values below come from PHD2 itself — adopt them in preference to any computed estimate.",
            evidence: evidence,
            candidateContributors: [],
            suggestedResponse: "Apply the suggested min-move RA / Dec values in Brain → Algorithms. The Guiding Assistant has already accounted for your current seeing.",
            relatedHelpTopicIds: [HelpTopic.guidingAssistant.rawValue],
            relatedPHD2Tools: [.guidingAssistant],
            confidence: .high,
            sourceAuthority: .phd2Measurement
        )
    }

}

// MARK: - CalibrationSanityAlertObserver

/// Surfaces PHD2's four named calibration sanity alerts verbatim from the log:
/// *Too Few Steps*, *Orthogonality Error*, *Questionable Rates*, *Inconsistent Results*.
/// Per design doc §6.2: "Pass-through with link to Calibration Review & Modification."
nonisolated struct CalibrationSanityAlertObserver: RecommenderGenerator {
    let identifier = "calibrationSanityAlertObserver"
    init() {}

    private static let alertPatterns: [(name: String, needles: [String])] = [
        ("Too Few Steps",       ["Too few steps", "too few steps for calibration", "Calibration steps too small"]),
        ("Orthogonality Error", ["non-orthogonal", "calibration angles", "orthogonality error", "Calibration angles look bad"]),
        ("Questionable Rates",  ["Questionable rates", "calibration rates"]),
        ("Inconsistent Results", ["Inconsistent results", "inconsistent calibration", "calibration result"]),
    ]

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        var observations: [RecommenderObservation] = []
        for session in context.sessions {
            for info in session.infos {
                let text = info.text
                for (name, needles) in Self.alertPatterns {
                    for needle in needles where text.localizedCaseInsensitiveContains(needle) {
                        observations.append(makeObservation(
                            alertName: name,
                            verbatimText: text,
                            rigProfileId: context.profile.id,
                            sessionStartedAt: session.startedAt
                        ))
                        // Stop after first match — don't double-fire on the same line
                        break
                    }
                }
            }
        }
        return observations
    }

    private func makeObservation(alertName: String,
                                 verbatimText: String,
                                 rigProfileId: UUID,
                                 sessionStartedAt: Date?) -> RecommenderObservation {
        RecommenderObservation(
            scope: .singleNight,
            rigProfileId: rigProfileId,
            nightRecordIds: [],
            sessionStartedAt: sessionStartedAt,
            category: .phd2Hygiene,
            severity: .pattern,
            title: "PHD2 calibration alert: \(alertName)",
            summary: "PHD2 flagged this calibration with a sanity alert. The recommender surfaces it verbatim rather than paraphrasing.",
            evidence: [
                EvidenceItem(label: "PHD2 alert", value: verbatimText)
            ],
            candidateContributors: [],
            suggestedResponse: "Open Calibration Review & Modification in PHD2 to inspect the calibration. If the alert recurs, the Calibration Assistant will run a fresh calibration with all sanity checks.",
            relatedHelpTopicIds: [HelpTopic.calibrationTroubleshooting.rawValue],
            relatedPHD2Tools: [.calibrationReviewModification, .calibrationAssistant],
            confidence: .high,
            sourceAuthority: .phd2BehaviorDocumented
        )
    }
}

// MARK: - MaxDurationLimitObserver

/// Counts frames where PHD2's pulse hit the Max RA / Max Dec duration ceiling.
/// Per design doc §6.2: when >5% of frames are rail-limited, surface an observation
/// citing PHD2's Advanced Settings page and the specific Max RA/Dec Duration values.
///
/// Corpus-calibrated tiers (from Edge-10m post-fix subset): 0% rail rate is healthy.
/// Tiers: >1% watch, >5% pattern, >15% alert.
nonisolated struct MaxDurationLimitObserver: RecommenderGenerator {
    let identifier = "maxDurationLimitObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        var observations: [RecommenderObservation] = []
        for session in context.sessions {
            let included = session.entries.filter { $0.included }
            guard included.count >= 20 else { continue }

            let maxRa = Double(session.mount.maxRADuration ?? 0)
            let maxDec = Double(session.mount.maxDecDuration ?? 0)
            guard maxRa > 0 || maxDec > 0 else { continue }

            let raRailCount = included.filter { Double(abs($0.raDuration)) >= maxRa * 0.99 && maxRa > 0 }.count
            let decRailCount = included.filter { Double(abs($0.decDuration)) >= maxDec * 0.99 && maxDec > 0 }.count
            let raRate = Double(raRailCount) / Double(included.count)
            let decRate = Double(decRailCount) / Double(included.count)
            let maxRate = max(raRate, decRate)

            guard maxRate >= 0.01 else { continue }   // <1% — not worth surfacing

            let severity: RecommenderObservation.Severity
            if maxRate >= 0.15      { severity = .alert }
            else if maxRate >= 0.05 { severity = .pattern }
            else                    { severity = .coaching }

            let axis = raRate > decRate ? "RA" : "Dec"
            let maxDur = axis == "RA" ? maxRa : maxDec
            let pct = Int((maxRate * 100).rounded())

            let evidence: [EvidenceItem] = [
                .init(label: "Frames at \(axis) max-duration limit", value: "\(pct)% of \(included.count)"),
                .init(label: "Current Max \(axis) Duration", value: "\(Int(maxDur)) ms"),
                .init(label: "RA rail rate", value: String(format: "%.1f%%", raRate * 100)),
                .init(label: "Dec rail rate", value: String(format: "%.1f%%", decRate * 100)),
            ]

            observations.append(RecommenderObservation(
                scope: .singleNight,
                rigProfileId: context.profile.id,
                nightRecordIds: [],
                sessionStartedAt: session.startedAt,
                category: .pattern,
                severity: severity,
                title: "Pulse-rail saturation on \(axis)",
                summary: "PHD2's \(axis) corrections are hitting the configured maximum duration on \(pct)% of frames. This means the algorithm wants a larger correction than the cap allows.",
                evidence: evidence,
                candidateContributors: [
                    "Max \(axis) Duration set too low for the rig's typical correction size",
                    "Aggressiveness setting that drives unusually large corrections",
                    "Mechanical issue causing the mount to fall behind tracking (cable drag, balance, stiction)",
                ],
                suggestedResponse: "Inspect Brain → Algorithms → Max \(axis) Duration. PHD2's documented behavior is to clip pulses at this value; raising it lets the algorithm reach its intended correction. If the rail rate persists at higher caps, investigate mechanical causes.",
                relatedHelpTopicIds: [HelpTopic.maxDurationLimits.rawValue],
                relatedPHD2Tools: [.guidingAssistant],
                confidence: .high,
                sourceAuthority: .phd2BehaviorDocumented
            ))
        }
        return observations
    }
}

// MARK: - CalibrationStalenessObserver

/// Calibration age relative to session date. Per design doc §6.2 (corpus-calibrated):
/// >21 days = coaching, >30 days = alert.
nonisolated struct CalibrationStalenessObserver: RecommenderGenerator {
    let identifier = "calibrationStalenessObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        guard let calibration = context.mostRecentCalibration,
              let calDate = calibration.startedAt,
              let firstSession = context.sessions.first(where: { $0.startedAt != nil }),
              let sessionDate = firstSession.startedAt
        else { return [] }

        let interval = sessionDate.timeIntervalSince(calDate)
        let days = interval / (24 * 3600)
        guard days >= 21 else { return [] }

        let severity: RecommenderObservation.Severity = days >= 30 ? .alert : .coaching
        let dayCount = Int(days.rounded())

        return [RecommenderObservation(
            scope: .singleNight,
            rigProfileId: context.profile.id,
            nightRecordIds: [],
            category: .phd2Hygiene,
            severity: severity,
            title: "Calibration is \(dayCount) days old",
            summary: "The calibration used for this session was run \(dayCount) days ago. PHD2's Best Practices document recommends recalibrating after equipment changes or substantial pointing shifts.",
            evidence: [
                .init(label: "Calibration date", value: calDate.formatted(date: .abbreviated, time: .omitted)),
                .init(label: "Session date", value: sessionDate.formatted(date: .abbreviated, time: .omitted)),
                .init(label: "Age", value: "\(dayCount) days"),
            ],
            candidateContributors: [],
            suggestedResponse: "Run the Calibration Assistant on your next session. It slews to the optimum sky position, pre-clears Dec backlash, and reports cal quality automatically.",
            relatedHelpTopicIds: [HelpTopic.calibrationStaleness.rawValue],
            relatedPHD2Tools: [.calibrationAssistant],
            confidence: .high,
            sourceAuthority: .phd2Manual
        )]
    }
}

// MARK: - CalibrationOrthogonalityObserver

/// Orthogonality error from the most recent calibration. Per design doc §6.2:
/// >5° = pattern, >10° = alert. Both reference Calibration Assistant + Star Cross.
nonisolated struct CalibrationOrthogonalityObserver: RecommenderGenerator {
    let identifier = "calibrationOrthogonalityObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        guard let calibration = context.mostRecentCalibration,
              let ortho = calibration.details.orthogonalityErrorDeg,
              ortho >= 5
        else { return [] }

        let severity: RecommenderObservation.Severity = ortho >= 10 ? .alert : .pattern
        let orthoStr = String(format: "%.1f°", ortho)

        return [RecommenderObservation(
            scope: .singleNight,
            rigProfileId: context.profile.id,
            nightRecordIds: [],
            category: .phd2Hygiene,
            severity: severity,
            title: "Calibration orthogonality error of \(orthoStr)",
            summary: "The angle between PHD2's measured RA and Dec calibration legs deviates by \(orthoStr) from 90°. PHD2's manual treats >5° as a sanity-alert candidate; >10° indicates a calibration that should be rerun.",
            evidence: [
                .init(label: "Orthogonality error", value: orthoStr),
                .init(label: "Threshold (pattern)", value: "5°"),
                .init(label: "Threshold (alert)", value: "10°"),
            ],
            candidateContributors: [
                "Calibration started too close to the celestial pole (small declination → unreliable Dec rate)",
                "Mount slop or balance changing the rate between RA and Dec legs",
                "Dec backlash not cleared before the calibration started",
            ],
            suggestedResponse: "Run the Calibration Assistant on your next session — it slews to the optimum sky position and pre-clears Dec backlash, which directly addresses the two most common orthogonality causes. The Star Cross Tool can confirm the mount responds correctly on both axes if the alert persists.",
            relatedHelpTopicIds: [HelpTopic.calibrationOrthogonality.rawValue],
            relatedPHD2Tools: [.calibrationAssistant, .starCross, .calibrationReviewModification],
            confidence: .high,
            sourceAuthority: .phd2Manual
        )]
    }
}

// MARK: - VariableExposureDelaysObserver

/// When the rig is encoder-based premium and Variable Exposure Delays appears not enabled,
/// recommend turning it on. PHD2's manual explicitly recommends this for encoder mounts.
nonisolated struct VariableExposureDelaysObserver: RecommenderGenerator {
    let identifier = "variableExposureDelaysObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        guard context.profile.mountClass == .encoderBasedPremium ||
              context.profile.hasHighPrecisionEncoders
        else { return [] }

        // Check the most recent session for the VED indicator
        guard let session = context.sessions.last else { return [] }
        let props = session.headerProperties
        guard !props.variableExposureDelaysEnabled else { return [] }

        return [RecommenderObservation(
            scope: .singleNight,
            rigProfileId: context.profile.id,
            nightRecordIds: [],
            category: .suggestion,
            severity: .suggestion,
            title: "Variable Exposure Delays not enabled",
            summary: "Your rig is configured as an encoder-based premium mount. PHD2's manual recommends Variable Exposure Delays specifically for this class — short exposures during setup, dither, and settle, then a long delay during steady-state guiding so PHD2 corrections don't fight the encoders.",
            evidence: [
                .init(label: "Mount class", value: context.profile.mountClass.displayName),
                .init(label: "High-precision encoders", value: context.profile.hasHighPrecisionEncoders ? "Yes" : "Not declared"),
                .init(label: "VED detected in header", value: "No"),
            ],
            candidateContributors: [],
            suggestedResponse: "Configure in PHD2: Brain → Camera tab → ☑ \"Use Variable Exposure Delays\" + Short delay (sec) + Long delay (sec). PHD2's manual: *\"Very precise/encoder-equipped mounts often benefit from conservative auto-guiding. This can include use of medium-long exposure times (4+ seconds) and an additional delay between guide camera exposures.\"*",
            relatedHelpTopicIds: [HelpTopic.variableExposureDelays.rawValue],
            relatedPHD2Tools: [],
            confidence: .medium,
            sourceAuthority: .phd2Manual
        )]
    }
}

// MARK: - MultiStarGuidingObserver

/// Recommends multi-star guiding when not active. Per PHD2 manual: "Multi-star guiding
/// greatly reduces the chance for the mount to chase after occasional seeing spikes."
nonisolated struct MultiStarGuidingObserver: RecommenderGenerator {
    let identifier = "multiStarGuidingObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        guard let session = context.sessions.last else { return [] }
        let props = session.headerProperties
        guard !props.multiStarEnabled else { return [] }

        return [RecommenderObservation(
            scope: .singleNight,
            rigProfileId: context.profile.id,
            nightRecordIds: [],
            category: .suggestion,
            severity: .suggestion,
            title: "Multi-star guiding not enabled",
            summary: "PHD2's multi-star mode uses an SNR-weighted centroid across several stars. PHD2's manual: *\"Multi-star guiding greatly reduces the chance for the mount to chase after occasional seeing spikes.\"*",
            evidence: [
                .init(label: "Multi-star detected in header", value: "No"),
            ],
            candidateContributors: [],
            suggestedResponse: "Enable in PHD2: Brain → Guiding tab → ☑ \"Use multiple stars\". Then click Auto-Select Stars to populate the centroid pool — the manual notes \"the auto-select function will nearly always do a better job than you can by just looking.\"",
            relatedHelpTopicIds: [HelpTopic.multiStarGuiding.rawValue],
            relatedPHD2Tools: [.autoSelectStars],
            confidence: .medium,
            sourceAuthority: .phd2Manual
        )]
    }
}

// MARK: - AlgorithmMismatchObserver

/// Compares the session's active algorithms against the mount-class recommendation matrix.
/// When they don't match, surfaces the specific delta with the source authority that backs
/// the recommendation (`phd2Manual` for canon classes, `communityConsensus` for harmonic).
nonisolated struct AlgorithmMismatchObserver: RecommenderGenerator {
    let identifier = "algorithmMismatchObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        guard let session = context.sessions.last else { return [] }
        let defaults = MountClassDefaults.defaults(for: context.profile.mountClass)
        var observations: [RecommenderObservation] = []

        if let raToken = session.mount.xGuideAlgorithm,
           let raAlg = PHD2Algorithm.fromLogToken(raToken),
           raAlg != defaults.recommendedRAAlgorithm {
            observations.append(makeObservation(
                axis: "RA",
                actual: raAlg,
                recommended: defaults.recommendedRAAlgorithm,
                profile: context.profile,
                authority: defaults.sourceAuthority
            ))
        }
        if let decToken = session.mount.yGuideAlgorithm,
           let decAlg = PHD2Algorithm.fromLogToken(decToken),
           decAlg != defaults.recommendedDecAlgorithm {
            observations.append(makeObservation(
                axis: "Dec",
                actual: decAlg,
                recommended: defaults.recommendedDecAlgorithm,
                profile: context.profile,
                authority: defaults.sourceAuthority
            ))
        }
        return observations
    }

    private func makeObservation(axis: String,
                                 actual: PHD2Algorithm,
                                 recommended: PHD2Algorithm,
                                 profile: RigProfile,
                                 authority: SourceAuthority) -> RecommenderObservation {
        let authorityNote = authority == .communityConsensus
            ? "This is community/vendor consensus; PHD2's manual is silent on this mount class."
            : "PHD2's manual recommends this algorithm for your mount class."

        return RecommenderObservation(
            scope: .singleNight,
            rigProfileId: profile.id,
            nightRecordIds: [],
            category: .suggestion,
            severity: .suggestion,
            title: "\(axis) algorithm: consider \(recommended.displayName)",
            summary: "Your rig is classified as \(profile.mountClass.displayName.lowercased()) and the session is running \(actual.displayName) on \(axis). \(authorityNote)",
            evidence: [
                .init(label: "Active \(axis) algorithm", value: actual.displayName),
                .init(label: "Recommended", value: recommended.displayName),
                .init(label: "Mount class", value: profile.mountClass.displayName),
            ],
            candidateContributors: [],
            suggestedResponse: "Switch in PHD2: Brain → Algorithms → \(axis) Algorithm. \(recommendationContext(recommended))",
            relatedHelpTopicIds: [HelpTopic.guideAlgorithms.rawValue],
            relatedPHD2Tools: [],
            confidence: .medium,
            sourceAuthority: authority
        )
    }

    private func recommendationContext(_ alg: PHD2Algorithm) -> String {
        switch alg {
        case .lowpass2:      return "PHD2's manual: *\"LowPass2 is a very conservative, high-impedance algorithm … the recommended algorithm for mounts that have high-precision encoders.\"*"
        case .hysteresis:    return "Hysteresis is the default RA algorithm for standard mounts and a safe baseline."
        case .resistSwitch:  return "Resist Switch is the default Dec algorithm and resists chasing seeing-induced direction reversals."
        case .predictivePEC: return "Predictive PEC issues proactive corrections from a Gaussian-process model of periodic error. Note: training takes ~2 worm periods; the model resets after slews."
        default:             return "See the PHD2 Guide Algorithms manual section for details."
        }
    }
}
