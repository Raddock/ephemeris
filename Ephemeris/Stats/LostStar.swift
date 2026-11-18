//
//  LostStar.swift
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

/// Finds the stretch at the end of a guiding session where guiding had lost
/// hold of the star: the star left PHD2's search region around the lock
/// position, kept moving away, and never came back before the session ended.
///
/// A session like that isn't guiding data. On an ASIAir night where the mount
/// stopped tracking, the star ran 1,300 px from the lock position while every
/// frame sent a maximum-length RA correction, and the recommender read that as
/// "elevated RMS, likely atmospheric". The recommender analyzes sessions with
/// these stretches cut off and reports the stretch itself separately.
///
/// The rule, measured against an ASIAir corpus (11 nights) and a NINA-driven
/// PHD2 corpus (56 nights) before it shipped:
/// - the session's included frames end with at least `minimumRunFrames` in a
///   row farther from the lock position than the header's search region, and
/// - over that run the star moved farther away by more than one search region,
///   comparing the median of the run's first three frames with its last three
///   (so one bad centroid can't make a steady offset look like a runaway), and
/// - guiding output was on for the whole run. PHD2 turns it off deliberately
///   (the Guiding Assistant measures unguided drift that way), and that drift
///   is measurement, not a lost star.
///
/// The second condition is what separates a lost star from an offset the star
/// sits at steadily: in the NINA logs, sessions that ended mid-settle after a
/// dither sat a few pixels past a 15 px search region without moving, and must
/// not count. With both conditions the rule flags 12 of 180 ASIAir sessions
/// (all runaways, hundreds of pixels) and 1 of 710 NINA sessions (a star that
/// drifted from 15 to 40 px over 20 minutes while no corrections went out).
nonisolated enum LostStar {

    /// A trailing stretch of a session in which guiding had lost the star.
    struct Run: Sendable, Equatable {
        /// Index into `session.entries` of the run's first frame. Entries from
        /// here on are the lost stretch; entries before it are kept.
        let firstEntryIndex: Int
        /// Included frames in the run.
        let frames: Int
        /// Distance from the lock position (px) at the run's first frame.
        let startDistancePx: Double
        /// Largest distance from the lock position (px) during the run.
        let maxDistancePx: Double
        /// Seconds from the run's first frame to the session's last frame,
        /// counting frames after it where PHD2 couldn't measure the star.
        /// Measured between valid timestamps only; 0 when none are usable.
        let durationSec: Double
        /// Frames after the run's first frame where PHD2 couldn't measure the
        /// star (star lost, low SNR): cut along with the run.
        let unmeasuredFrames: Int
        /// The header's search region (px) the run was measured against.
        let searchRegionPx: Double
        /// Frames in the run that sent an RA correction.
        let raCorrectedFrames: Int
        /// Frames in the run that sent a Dec correction.
        let decCorrectedFrames: Int
        /// Frames in the run that sent a correction on either axis.
        let correctedFrames: Int
        /// Frames in the run whose RA correction was the session's maximum RA
        /// duration (nil when the header doesn't state one).
        let raMaxedFrames: Int?
        /// The session's maximum RA duration (ms), when the header states one.
        let maxRADurationMs: Int?
    }

    /// Minimum run length. Five frames is a few seconds to a minute of
    /// guiding: long enough that a single bad centroid can't trigger it.
    static let minimumRunFrames = 5

    /// PHD2's default search region, used when the header doesn't state one.
    static let defaultSearchRegionPx = 15.0

    /// Below this many included frames, what's left of a session after its
    /// lost stretch is cut off is too short to analyze and is dropped.
    static let minimumKeptFrames = 10

    /// The lost stretch at the end of `session`, or nil when guiding held the
    /// star to the end (or the session is too short to tell).
    static func detect(in session: GuideSession) -> Run? {
        // A merged session (the viewer's combined-session mode, marked by NaN
        // boundary sentinels) carries only its first source session's header,
        // so the search region for the session whose end this checks is
        // unknown. Don't guess; the normal view and the Library analyze each
        // session with its own header.
        guard !session.entries.contains(where: { $0.raRawDistance.isNaN }) else { return nil }
        let region = searchRegionPx(in: session.rawHeader) ?? defaultSearchRegionPx
        // Walk back from the session's end collecting measured frames past the
        // search region. Frames with no usable position (dropped, or a
        // non-finite value from a malformed row) neither join nor break the run.
        var runIndices: [Int] = []
        var index = session.entries.endIndex
        while index > session.entries.startIndex {
            index -= 1
            let entry = session.entries[index]
            guard entry.included, entry.raRawDistance.isFinite, entry.decRawDistance.isFinite else { continue }
            guard distance(entry) > region else { break }
            runIndices.append(index)
        }
        runIndices.reverse()
        let run = runIndices.map { (offset: $0, element: session.entries[$0]) }
        guard run.count >= minimumRunFrames, let first = run.first else { return nil }
        // Guiding output deliberately off (Guiding Assistant, or turned off by
        // the user or imaging software): drift then is expected, not lost.
        guard run.allSatisfy({ $0.element.guiding }) else { return nil }

        // Sustained outward movement: the end of the run against its start,
        // three frames each, so a single spike can't qualify a steady offset.
        let distances = run.map { distance($0.element) }
        let startLevel = median(distances.prefix(3))
        let endLevel = median(distances.suffix(3))
        guard endLevel - startLevel > region else { return nil }

        let startDistance = distances[0]
        let maxDistance = distances.max() ?? startDistance
        let tail = session.entries[first.offset...]
        let measured = { (entry: GuideEntry) in
            entry.included && entry.raRawDistance.isFinite && entry.decRawDistance.isFinite
        }
        // Length from valid timestamps only: the parser accepts "nan" or "inf"
        // in the Time field of a malformed row.
        let finiteTimes = tail.map(\.time).filter(\.isFinite)
        let duration = max(0, (finiteTimes.last ?? 0) - (finiteTimes.first ?? 0))

        // The header parser reads max durations only from the "Mount = " line;
        // PHD2 2.6 and the ASIAir write them on the "Calibration step = " line.
        let maxRA = session.mount.maxRADuration ?? maxRADurationMs(in: session.rawHeader)
        return Run(
            firstEntryIndex: first.offset,
            frames: run.count,
            startDistancePx: startDistance,
            maxDistancePx: maxDistance,
            durationSec: duration,
            unmeasuredFrames: tail.filter { !measured($0) }.count,
            searchRegionPx: region,
            raCorrectedFrames: run.filter { $0.element.raDuration != 0 }.count,
            decCorrectedFrames: run.filter { $0.element.decDuration != 0 }.count,
            correctedFrames: run.filter { $0.element.raDuration != 0 || $0.element.decDuration != 0 }.count,
            raMaxedFrames: maxRA.map { limit in
                // .magnitude, not abs(): a damaged row can hold Int.min, and
                // abs(Int.min) traps.
                run.filter { limit > 0 && $0.element.raDuration.magnitude >= UInt(limit) }.count
            },
            maxRADurationMs: maxRA
        )
    }

    /// One session's lost stretch, paired with the session as logged.
    struct Finding: Sendable {
        let session: GuideSession
        let run: Run
    }

    /// The night as the recommender should analyze it: each session with its
    /// lost stretch cut off, and sessions dropped when too little is left.
    /// Calibrations and everything else are unchanged. Also returns what was
    /// found, so the stretches can be reported on their own.
    static func analysisView(of log: GuideLog) -> (log: GuideLog, findings: [Finding]) {
        var findings: [Finding] = []
        var kept: [GuideSession] = []
        for session in log.guideSessions {
            guard let run = detect(in: session) else {
                kept.append(session)
                continue
            }
            findings.append(Finding(session: session, run: run))
            var trimmed = session
            trimmed.entries = Array(session.entries[..<run.firstEntryIndex])
            let lastKeptFrame = trimmed.entries.last?.frame ?? Int.min
            trimmed.infos = session.infos.filter { $0.frame <= lastKeptFrame }
            let keptFrames = trimmed.entries.filter { $0.included && !$0.raRawDistance.isNaN }.count
            if keptFrames >= minimumKeptFrames {
                kept.append(trimmed)
            }
        }
        guard !findings.isEmpty else { return (log, []) }

        var view = log
        view.guideSessions = kept
        // Rebuild the section index so `.guide(i)` still points at the right
        // session; calibrations keep their indices.
        var sections: [GuideLog.SectionRef] = []
        var guideIndex = 0
        let keptIDs = Set(kept.map(\.id))
        var originalGuide = 0
        for section in log.sections {
            switch section {
            case .guide:
                if keptIDs.contains(log.guideSessions[originalGuide].id) {
                    sections.append(.guide(guideIndex))
                    guideIndex += 1
                }
                originalGuide += 1
            default:
                sections.append(section)
            }
        }
        view.sections = sections
        return (view, findings)
    }

    // MARK: - Helpers

    private static func median<C: Collection>(_ values: C) -> Double where C.Element == Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func distance(_ entry: GuideEntry) -> Double {
        (entry.raRawDistance * entry.raRawDistance + entry.decRawDistance * entry.decRawDistance).squareRoot()
    }

    /// "Max RA duration = 2500" from whichever header line carries it.
    static func maxRADurationMs(in header: [String]) -> Int? {
        for line in header {
            guard let range = line.range(of: "Max RA duration = ") else { continue }
            if let value = Int(line[range.upperBound...].prefix { $0.isNumber }), value > 0 { return value }
        }
        return nil
    }

    /// "Search region = 15 px, ..." from the guiding header.
    static func searchRegionPx(in header: [String]) -> Double? {
        for line in header {
            guard let range = line.range(of: "Search region = ") else { continue }
            let digits = line[range.upperBound...].prefix { $0.isNumber || $0 == "." }
            if let value = Double(digits), value > 0 { return value }
        }
        return nil
    }
}
