//
//  LostStarObserver.swift
//  Ephemeris
//
//  Copyright (C) 2026 Andrew Burwell
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

/// Reports each stretch where guiding had lost the star (`LostStar`), in place
/// of the diagnoses other generators used to draw from it. One observation per
/// affected session, anchored to that session.
///
/// What was measured comes first (distances, duration, corrections sent), then
/// what it usually means, then what would tell the possibilities apart. Whether
/// corrections were going out splits the two cases: corrections at work while
/// the star keeps moving away points at a mount not acting on them; no
/// corrections points at guiding output being paused or off.
nonisolated struct LostStarObserver: RecommenderGenerator {
    let identifier = "lostStarObserver"
    init() {}

    func observe(context: SingleNightContext) -> [RecommenderObservation] {
        context.lostStar.map { finding in
            observation(for: finding, context: context)
        }
    }

    private func observation(for finding: LostStar.Finding, context: SingleNightContext) -> RecommenderObservation {
        let run = finding.run
        let session = finding.session
        // A corrupt timestamp can make the length meaningless; never let it
        // reach Int(...), which traps.
        let span: String?
        if run.durationSec.isFinite, run.durationSec > 0, run.durationSec < 7 * 24 * 3600 {
            span = run.durationSec >= 60
                ? String(format: "%.1f minutes", run.durationSec / 60)
                : "\(Int(run.durationSec.rounded())) seconds"
        } else {
            span = nil
        }
        let lead = span.map { "For the last \($0) of this session" } ?? "At the end of this session"
        let from = px(run.startDistancePx)
        let to = px(run.maxDistancePx)
        let region = px(run.searchRegionPx)
        // Corrections on either axis: a star running away in Dec while Dec
        // corrections go out is not "guiding output off".
        let noneCorrected = run.correctedFrames == 0
        let allCorrected = run.correctedFrames == run.frames

        var corrections: String
        if noneCorrected {
            corrections = "None of those \(run.frames) frames sent a guide correction on either axis."
        } else {
            corrections = allCorrected
                ? "All \(run.frames) of those frames sent a guide correction"
                : "\(run.correctedFrames) of those \(run.frames) frames sent a guide correction"
            if let maxed = run.raMaxedFrames, maxed > 0, let limit = run.maxRADurationMs {
                corrections += maxed == run.correctedFrames
                    ? ", each an RA correction at the \(limit) ms maximum."
                    : ", \(maxed) of them an RA correction at the \(limit) ms maximum."
            } else {
                corrections += "."
            }
        }
        if run.unmeasuredFrames > 0 {
            corrections += " PHD2 also couldn't measure the star in \(run.unmeasuredFrames) frame\(run.unmeasuredFrames == 1 ? "" : "s") of this stretch."
        }

        let meaning = noneCorrected
            ? "With no corrections going out while the star was this far off, guiding output was most likely paused or turned off."
            : "Corrections going out while the star keeps moving away usually means the mount wasn't acting on them."

        var evidence: [EvidenceItem] = [
            .init(label: "Distance from lock position", value: "\(from) to \(to)"),
            .init(label: "PHD2 search region", value: region),
            .init(label: "Length", value: span.map { "\($0), \(run.frames) measured frames" } ?? "\(run.frames) measured frames"),
            .init(label: "Corrections sent", value: "RA in \(run.raCorrectedFrames), Dec in \(run.decCorrectedFrames) of \(run.frames) frames"),
        ]
        if run.unmeasuredFrames > 0 {
            evidence.append(.init(label: "Frames with the star unmeasured", value: "\(run.unmeasuredFrames)"))
        }
        let props = session.headerProperties
        if let dec = props.decDegrees, let ha = props.hourAngleHours {
            evidence.append(.init(label: "Mount position at session start",
                                  value: String(format: "Dec %.1f°, hour angle %.2f h", dec, ha)))
        }

        let contributors = noneCorrected
            ? [
                "Guiding output paused or turned off by the imaging software",
                "The mount not tracking while corrections were paused",
            ]
            : [
                "Mount tracking stopped, or never started (a parked or homed mount still reports a position)",
                "The mount slewing or being moved while guiding ran",
                "Guide commands not reaching the mount (cable, driver, or connection)",
            ]

        var response = "Nothing here calls for a change to the guiding settings: this stretch isn't guiding data, and Ephemeris leaves it out of its other observations. The imaging software's log for the same time would show whether the mount was tracking, slewing, or parked."
        if context.rawLog.isASIAir {
            response += " On an ASIAir, the Autorun log saved with this guide log records when tracking started and when each guiding attempt began."
        }

        return RecommenderObservation(
            scope: .singleNight,
            rigProfileId: context.profile.id,
            nightRecordIds: [],
            sessionStartedAt: session.startedAt,
            category: .equipment,
            severity: .equipment,
            title: "Guiding lost the star",
            summary: "\(lead) the guide star moved from \(from) to \(to) away from the lock position and never came back inside PHD2's \(region) search region. \(corrections) \(meaning)",
            evidence: evidence,
            candidateContributors: contributors,
            suggestedResponse: response,
            relatedHelpTopicIds: [HelpTopic.whatTheGuideLogCantTellYou.rawValue, HelpTopic.readingTheGuideLog.rawValue],
            relatedPHD2Tools: [],
            confidence: .medium,
            sourceAuthority: .ephemerisHeuristic
        )
    }

    /// Never traps: a corrupt row can carry a distance too large for Int.
    private func px(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1e12 else { return "an unmeasurable distance" }
        return "\(Int(value.rounded()).formatted()) px"
    }
}
