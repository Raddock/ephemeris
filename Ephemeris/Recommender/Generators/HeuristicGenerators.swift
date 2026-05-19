import Foundation

// MARK: - DecPolarityBiasObserver

/// Three-guard polarity-bias check (design doc §6.2, corpus-calibrated):
/// fire only when Dec polarity skew >70% AND |Dec drift| >0.03″/min.
/// (The full design also requires polar-align variance across last 5 sessions > 30%, but
/// that needs cross-night context — added in Phase 7.)
///
/// Without the three-guard rule, this generator would fire on ~90% of healthy encoder-mount
/// sessions in the corpus (median Dec skew 50%, p90 100% on a well-aligned 10Micron). The
/// guards exist to prevent that false-fire.
struct DecPolarityBiasObserver: RecommenderGenerator {
    let identifier = "decPolarityBiasObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        var observations: [RecommenderObservation] = []
        for (session, stats) in context.sessionStats {
            let included = session.entries.filter { $0.included }
            let decPulses: [Int] = included.compactMap { entry in
                entry.decDuration != 0 ? entry.decDuration : nil
            }
            guard decPulses.count >= 20 else { continue }
            let neg = decPulses.filter { $0 < 0 }.count
            let pos = decPulses.filter { $0 > 0 }.count
            let total = max(1, neg + pos)
            let skew = abs(Double(neg - pos)) / Double(total)
            guard skew > 0.70 else { continue }

            // Convert drift to arcsec/min. SessionStatsCalculator returns drift in px/min.
            let driftDecArcsecPerMin = abs(stats.driftDec) * session.pixelScale
            guard driftDecArcsecPerMin > 0.03 else { continue }

            observations.append(RecommenderObservation(
                scope: .singleNight,
                rigProfileId: context.profile.id,
                nightRecordIds: [],
                category: .pattern,
                severity: .pattern,
                title: "Dec corrections heavily one-directional",
                summary: "Dec polarity skew of \(Int((skew * 100).rounded()))% combined with a measurable Dec drift suggests a systematic polar-alignment offset rather than seeing chase.",
                evidence: [
                    .init(label: "Dec polarity skew", value: "\(Int((skew * 100).rounded()))%"),
                    .init(label: "|Dec drift|", value: String(format: "%.3f″/min", driftDecArcsecPerMin)),
                    .init(label: "Threshold (skew)", value: "70%"),
                    .init(label: "Threshold (drift)", value: "0.03″/min"),
                ],
                candidateContributors: [
                    "Polar-alignment offset producing systematic Dec drift in one direction",
                    "Mount sky model needing refresh (for encoder mounts with refraction modeling)",
                    "Differential flexure pulling the guide camera relative to the imager",
                ],
                suggestedResponse: "Run the Guiding Assistant — it measures polar-alignment error directly. If the GA reports >5 arcmin, run Drift Alignment or Static Polar Alignment to correct.",
                relatedHelpTopicIds: ["polar-alignment-fundamentals"],
                relatedPHD2Tools: [.guidingAssistant, .driftAlignment, .staticPolarAlignment],
                confidence: .medium,
                sourceAuthority: .ephemerisHeuristic
            ))
        }
        return observations
    }
}

// MARK: - AtmosphericConditionsProxy

/// "Don't chase this" observation. When star mass coefficient-of-variation is high,
/// altitude is low, and RMS is elevated, the most likely cause is the atmosphere, not equipment.
///
/// Per the corpus correlation analysis (§13.4): on a healthy premium rig, star mass CV
/// correlates with RMS at r=+0.77; altitude correlates at r=-0.65. Within-night variance is
/// 61% of total — confirming that conditions drive RMS more than equipment state.
///
/// Without cross-night rig baselines (added in Phase 7), this generator uses absolute thresholds:
/// star mass CV > 15% + altitude < 50° + RMS > 0.7″ together.
struct AtmosphericConditionsProxy: RecommenderGenerator {
    let identifier = "atmosphericConditionsProxy"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        var observations: [RecommenderObservation] = []
        for (session, stats) in context.sessionStats {
            guard stats.includedFrames >= 30 else { continue }
            let masses = session.entries
                .filter { $0.included && $0.starMass > 0 }
                .map { Double($0.starMass) }
            guard masses.count >= 30 else { continue }
            let mean = masses.reduce(0, +) / Double(masses.count)
            guard mean > 0 else { continue }
            let variance = masses.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(masses.count)
            let cv = sqrt(variance) / mean

            let rmsArcsec = stats.rmsTotal * session.pixelScale
            let props = session.headerProperties
            let altitude = props.altitudeDegrees ?? 90  // assume high if unknown

            let highCv = cv > 0.15
            let lowAlt = altitude < 50
            let elevatedRms = rmsArcsec > 0.7

            // Need at least two of three to fire — single signal is too noisy
            let signals = [highCv, lowAlt, elevatedRms].filter { $0 }.count
            guard signals >= 2 else { continue }

            var evidence: [EvidenceItem] = [
                .init(label: "Total RMS", value: String(format: "%.2f″", rmsArcsec)),
                .init(label: "Star mass CV", value: String(format: "%.0f%%", cv * 100)),
            ]
            if props.altitudeDegrees != nil {
                evidence.append(.init(label: "Altitude", value: String(format: "%.0f°", altitude)))
            }

            observations.append(RecommenderObservation(
                scope: .singleNight,
                rigProfileId: context.profile.id,
                nightRecordIds: [],
                category: .pattern,
                severity: .coaching,
                title: "Elevated RMS — likely atmospheric, not equipment",
                summary: "This session's RMS is elevated, but the combination of star-flux variability and \(props.altitudeDegrees != nil ? "low altitude" : "other signals") points toward atmospheric instability rather than mount or optical-train state. PHD2 guide logs cannot distinguish seeing from transparency directly — this is a coaching observation only.",
                evidence: evidence,
                candidateContributors: [
                    "Atmospheric scintillation (transparency / seeing instability)",
                    "Low target altitude — thicker atmospheric path",
                    "Thin cirrus or partial transparency changes during the session",
                ],
                suggestedResponse: "No equipment action is recommended on the basis of this single session. If you have eyes-on at the site, an atmospheric annotation (haze, scintillation visible by eye) helps the recommender contextualize this night. PHD2's Guiding Assistant reports its own seeing measurement; running it on a clearer night gives a reference baseline.",
                relatedHelpTopicIds: ["seeing-vs-equipment", "what-the-guide-log-cant-tell-you"],
                relatedPHD2Tools: [.guidingAssistant],
                confidence: .medium,
                sourceAuthority: .ephemerisHeuristic
            ))
        }
        return observations
    }
}
