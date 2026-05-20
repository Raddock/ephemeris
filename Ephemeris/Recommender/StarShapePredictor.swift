import Foundation

/// What the data alone predicts a night's stars will look like.
///
/// The five outcomes — including a `bloated` flag on `round` — map onto
/// `SubQualityVerdict` for the "predicted vs rated" disagreement check.
/// Bloated round is a distinct state from elongated: a harmonic-strain-wave
/// mount carrying a long-focal-length OTA may guide symmetrically at 0.65″
/// on a 0.40″/px setup. Stars are still round (no axis asymmetry, no drift)
/// — just larger than they would be if guiding were sub-pixel. A user
/// rating this night would still pick `.round` from their visual check, so
/// the verdict mapping treats both sharp and bloated round as `.round`.
enum PredictedStarShape: Sendable, Equatable {
    /// Symmetric guiding (low axis asymmetry, no meaningful drift). `bloated == true`
    /// means RMS exceeds the imaging scale enough that stars will look noticeably
    /// soft despite being round — the classic "good guiding, long focal length,
    /// imaging scale tighter than the mount can hit" signature.
    case round(bloated: Bool)
    /// Axis-asymmetric guiding (one axis distinctly worse than the other). Produces
    /// egg-shaped stars regardless of total RMS.
    case slightlyElongated
    /// One-axis drift large enough to cross multiple imaging pixels over a typical sub.
    /// `cause` identifies which axis dominated, since the diagnosis differs:
    ///   - `.decDrift` is the canonical polar-alignment-error signature
    ///   - `.raDrift` points at periodic-error, wind, or tracking-rate issues
    ///   - `.bothAxes` is rarer — usually mount tracking or modeling failure
    case trailed(cause: TrailedCause)
    /// Sessions disagree across the night (huge best-to-worst spread) — likely a
    /// transparency / wind / mid-session-event signature.
    case mixed
    /// Not enough data to predict (no imaging scale configured, no sessions logged).
    case unknown

    enum TrailedCause: Sendable, Equatable {
        case decDrift          // polar alignment error
        case raDrift           // PE / wind / rate
        case bothAxes          // mount tracking failure
    }

    var verdict: SubQualityVerdict? {
        switch self {
        case .round:              return .round
        case .slightlyElongated:  return .slightlyElongated
        case .trailed:            return .trailed
        case .mixed:              return .mixed
        case .unknown:            return nil
        }
    }

    var displayName: String {
        switch self {
        case .round(let bloated): return bloated ? "Round (bloated)" : "Round"
        case .slightlyElongated:  return "Slightly elongated"
        case .trailed(let cause):
            switch cause {
            case .decDrift:  return "Trailed (Dec drift)"
            case .raDrift:   return "Trailed (RA drift)"
            case .bothAxes:  return "Trailed (both axes)"
            }
        case .mixed:              return "Mixed"
        case .unknown:            return "Unknown"
        }
    }

    /// True only for the bloated-round variant. Used by the UI to decorate the
    /// `.round` chip with a "soft" annotation without forcing the user-rated
    /// disagreement check to fire.
    var isBloated: Bool {
        if case .round(let bloated) = self { return bloated }
        return false
    }
}

/// Pure-function predictor for a single night's likely star shape. Driven entirely
/// from the data we already capture: per-session RMS-RA / RMS-Dec / drift /
/// included-frames, plus the rig's imaging pixel scale.
///
/// Logic (in order; first match wins):
///   1. **Trailed** — one-axis drift, projected across a typical sub-exposure, exceeds
///      2× the imaging pixel scale. That's enough motion to traverse multiple pixels
///      during a single sub, so stars become visibly elongated lines.
///   2. **Mixed** — the spread between the night's best and worst session RMS is
///      > 3×, meaning conditions or equipment state varied substantially mid-night.
///      The user's eye will see "some good, some bad" subs.
///   3. **Slightly elongated** — axis-asymmetric guiding (RMS-RA vs RMS-Dec ratio
///      exceeds 1.5×), OR RMS comfortably exceeds the imaging scale (≥ 1.5×). The
///      first form produces egg-shaped stars; the second produces soft, bloated ones
///      that the user's eye will read as "slightly elongated / off-round".
///   4. **Round** — everything else. Sub-pixel guiding with low asymmetry, or
///      mildly-over-scale-but-symmetric (bloated round, but still read as round).
///   5. **Unknown** — no imaging scale configured, or no session detail yet.
///
/// We assume a typical sub-exposure of 5 minutes for the drift→trailing calculation.
/// That's a reasonable mid-point for DSLR-class to dedicated-CCD imaging; users running
/// 1-min subs or 15-min narrowband would skew the trailed threshold, but the rough
/// bucketing is robust enough across that range.
nonisolated enum StarShapePredictor {

    struct Input: Sendable {
        let imagingPixelScale: Double  // arcsec/px (0 = not configured)
        let medianRMSArcsec: Double    // night-level rollup
        let bestSessionRMSArcsec: Double
        let worstSessionRMSArcsec: Double
        /// Per-session axis RMS / drift. May be empty if session records aren't
        /// populated yet (pre-Phase-10 ingest).
        let sessions: [SessionDigest]

        struct SessionDigest: Sendable {
            let rmsRAArcsec: Double
            let rmsDecArcsec: Double
            let driftRAArcsecPerMin: Double
            let driftDecArcsecPerMin: Double
            let includedFrames: Int
        }
    }

    static let typicalSubExposureMin: Double = 5.0
    /// Trailed = drift × sub-exposure crosses N imaging pixels. 4× is the threshold
    /// where an eye distinguishes "round but soft" from "lined out" — 2× was too
    /// trigger-happy and flipped most nights with a single noisy short session.
    static let trailedDriftScaleMultiplier: Double = 4.0
    static let mixedBestWorstRatio: Double = 3.0
    static let asymmetryRatio: Double = 1.5
    /// Once RMS exceeds this multiple of the imaging scale, symmetric guiding still
    /// produces visibly soft (bloated) stars. They remain round, not elongated.
    static let bloatedScaleMultiplier: Double = 1.25
    /// Sessions need at least this many frames to participate in trailed voting.
    /// Below this, linear-regression drift slope is too noisy to be meaningful.
    static let minFramesForTrailedVote: Int = 60
    /// Majority threshold for trailed verdict — > half the night's frame-weighted
    /// sessions must individually be trailed. Otherwise an outlier session can't
    /// flip a whole multi-session night.
    static let trailedMajorityFraction: Double = 0.5

    static func predict(_ input: Input) -> PredictedStarShape {
        guard input.imagingPixelScale > 0, input.medianRMSArcsec > 0 else {
            return .unknown
        }

        // 1. Trailed — frame-weighted majority of sessions must individually be trailed
        //    before we tag the whole night. A single bad short session in a multi-session
        //    night should produce .mixed at worst, not .trailed. Sessions with too few
        //    frames don't get a vote (slope from a 30-frame session is meaningless).
        let driftPerSubLimit = trailedDriftScaleMultiplier * input.imagingPixelScale
        var votingFrames = 0
        var raTrailedFrames = 0
        var decTrailedFrames = 0
        for s in input.sessions where s.includedFrames >= minFramesForTrailedVote {
            votingFrames += s.includedFrames
            let raDrift = abs(s.driftRAArcsecPerMin) * typicalSubExposureMin
            let decDrift = abs(s.driftDecArcsecPerMin) * typicalSubExposureMin
            if raDrift > driftPerSubLimit  { raTrailedFrames += s.includedFrames }
            if decDrift > driftPerSubLimit { decTrailedFrames += s.includedFrames }
        }
        if votingFrames > 0 {
            let raTrailedShare = Double(raTrailedFrames) / Double(votingFrames)
            let decTrailedShare = Double(decTrailedFrames) / Double(votingFrames)
            let raTrailed = raTrailedShare > trailedMajorityFraction
            let decTrailed = decTrailedShare > trailedMajorityFraction
            if raTrailed && decTrailed { return .trailed(cause: .bothAxes) }
            if decTrailed              { return .trailed(cause: .decDrift) }
            if raTrailed               { return .trailed(cause: .raDrift) }
        }

        // 2. Mixed — best-to-worst spread within the night is large.
        if input.bestSessionRMSArcsec > 0,
           input.worstSessionRMSArcsec > input.bestSessionRMSArcsec * mixedBestWorstRatio {
            return .mixed
        }

        // 3. Axis asymmetry across the night (weighted by frame count if available)
        //    — the only condition that produces elongated rather than bloated stars.
        let asymmetry = aggregateAsymmetry(sessions: input.sessions)
        if let asymmetry, asymmetry > asymmetryRatio {
            return .slightlyElongated
        }

        // 4. Symmetric guiding → always round, with `bloated` flag when RMS exceeds
        //    the imaging scale enough that stars look soft. Harmonic mounts on long-
        //    FL OTAs are the canonical example: 0.65″ RMS at 0.40″/px = 1.6× scale
        //    → round but bloated.
        let scaleRatio = input.medianRMSArcsec / input.imagingPixelScale
        return .round(bloated: scaleRatio >= bloatedScaleMultiplier)
    }

    /// Frame-count-weighted ratio of `max(rmsRA, rmsDec) / min(rmsRA, rmsDec)` across
    /// the night's sessions. Returns nil if no session has both axes recorded.
    private static func aggregateAsymmetry(sessions: [Input.SessionDigest]) -> Double? {
        var weightedSum = 0.0
        var totalFrames = 0
        for s in sessions where s.rmsRAArcsec > 0 && s.rmsDecArcsec > 0 && s.includedFrames > 0 {
            let ratio = max(s.rmsRAArcsec, s.rmsDecArcsec) / min(s.rmsRAArcsec, s.rmsDecArcsec)
            weightedSum += ratio * Double(s.includedFrames)
            totalFrames += s.includedFrames
        }
        guard totalFrames > 0 else { return nil }
        return weightedSum / Double(totalFrames)
    }
}

/// Convenience wrapper that builds an `Input` from a `NightRecordEntity` + the
/// rig's imaging scale. Pulls per-session axis breakdown from the related
/// `SessionRecordEntity` rows if they've been ingested.
@MainActor
extension StarShapePredictor {
    static func predict(night: NightRecordEntity, imagingPixelScale: Double) -> PredictedStarShape {
        let digests: [Input.SessionDigest] = (night.sessionRecords ?? []).map { s in
            Input.SessionDigest(
                rmsRAArcsec: s.rmsRAArcsec,
                rmsDecArcsec: s.rmsDecArcsec,
                driftRAArcsecPerMin: s.driftRAArcsecPerMin,
                driftDecArcsecPerMin: s.driftDecArcsecPerMin,
                includedFrames: s.includedFrames
            )
        }
        return predict(Input(
            imagingPixelScale: imagingPixelScale,
            medianRMSArcsec: night.medianRMSArcsec,
            bestSessionRMSArcsec: night.bestSessionRMSArcsec,
            worstSessionRMSArcsec: night.worstSessionRMSArcsec,
            sessions: digests
        ))
    }
}
