//
//  GuideSessionMerger.swift
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

enum GuideSessionMerger {

    /// Merge multiple guide sessions into one synthesized session, ordered by
    /// `startedAt`. Per-frame timestamps are rebased so the earliest session
    /// starts at t=0; subsequent sessions retain their real wall-clock offsets,
    /// so cross-session gaps (cloud breaks, meridian flips, manual restarts)
    /// appear naturally on the combined timeline.
    ///
    /// When timestamps are missing, sessions are concatenated end-to-end with a
    /// 1-second gap between them as a degenerate fallback.
    static func merge(_ sessions: [GuideSession]) -> GuideSession {
        guard !sessions.isEmpty else { return GuideSession() }
        if sessions.count == 1 { return sessions[0] }

        let sorted = sessions.sorted {
            ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast)
        }

        if let baseDate = sorted.first?.startedAt,
           sorted.allSatisfy({ $0.startedAt != nil }) {
            return mergeUsingDates(sorted, baseDate: baseDate)
        }
        return mergeBySequencing(sorted)
    }

    private static func mergeUsingDates(
        _ sorted: [GuideSession],
        baseDate: Date
    ) -> GuideSession {
        var merged = baseSession(from: sorted, startedAt: baseDate)
        var maxFrame = 0
        for (i, session) in sorted.enumerated() {
            let offset = session.startedAt!.timeIntervalSince(baseDate)
            // Insert a sentinel between sessions so SwiftUI Charts breaks the
            // RA/Dec lines at session boundaries instead of drawing a long
            // straight line across the wall-clock gap.
            if i > 0, let prevTime = merged.entries.last?.time,
               let firstEntry = session.entries.first {
                let boundaryTime = (prevTime + firstEntry.time + offset) / 2
                merged.entries.append(makeBoundaryEntry(at: boundaryTime, frame: maxFrame + 1))
                maxFrame += 1
            }
            for var entry in session.entries {
                entry.time += offset
                entry.frame += maxFrame
                merged.entries.append(entry)
            }
            for var info in session.infos {
                info.frame += maxFrame
                merged.infos.append(info)
            }
            if let last = merged.entries.last { maxFrame = last.frame }
        }
        return merged
    }

    private static func mergeBySequencing(_ sorted: [GuideSession]) -> GuideSession {
        var merged = baseSession(from: sorted, startedAt: sorted.first?.startedAt)
        var offset = 0.0
        var maxFrame = 0
        for (i, session) in sorted.enumerated() {
            if i > 0, let prevTime = merged.entries.last?.time {
                merged.entries.append(makeBoundaryEntry(at: prevTime + 0.5, frame: maxFrame + 1))
                maxFrame += 1
            }
            for var entry in session.entries {
                entry.time += offset
                entry.frame += maxFrame
                merged.entries.append(entry)
            }
            for var info in session.infos {
                info.frame += maxFrame
                merged.infos.append(info)
            }
            if let last = merged.entries.last {
                offset = last.time + 1.0
                maxFrame = last.frame
            }
        }
        return merged
    }

    /// A non-included sentinel placed between two source sessions. The NaN
    /// raw-distance / dx / dy values cause Swift Charts to break the main
    /// RA / Dec lines at this point.
    ///
    /// Sentinels must be filtered out of every read site that walks
    /// `GuideSession.entries` directly. Filtering on `\.included` is too
    /// coarse — it would also drop parser-flagged frames (errorCode > 1, e.g.
    /// star lost), which the UI explicitly wants to surface. The correct
    /// discriminator is `!entry.raRawDistance.isNaN` (only sentinels carry
    /// NaN; real frames always have finite values).
    ///
    /// Current sentinel-aware read sites (all use the NaN discriminator):
    /// 1. `GuideSession.frameCount`
    /// 2. `SessionStatsCalculator.calculate` (the `realEntries` filter)
    /// 3. `GuideGraphView.activeEntry` (chart hover / pin)
    /// 4. `GuideGraphView.entryTime(forFrame:)` (settling bands, event rules)
    /// 5. `SessionInspectorView.time(forInfoFrame:in:)` (click-to-jump)
    /// 6. `DiagnosticGraphView.realEntries` (line marks + active-entry hover)
    /// 7. `CSVExporter.frameDataCSV` (frame data export)
    ///
    /// `ScatterInsetView` is implicitly safe — it filters by `entry.included`
    /// before plotting and a sentinel's `included` is false; if scatter ever
    /// stops filtering by included, switch it to the NaN discriminator.
    /// Non-`frameDataCSV` exporters (`sessionStatsCSV`, `aggregateCSV`) read
    /// through `SessionStatsCalculator`, so they inherit the filter for free.
    ///
    /// When adding new code that walks `session.entries`, decide whether
    /// sentinels should be visible there and add the filter if not.
    private static func makeBoundaryEntry(at time: Double, frame: Int) -> GuideEntry {
        GuideEntry(
            frame: frame,
            time: time,
            deviceKind: .mount,
            dx: .nan, dy: .nan,
            raRawDistance: .nan, decRawDistance: .nan,
            raGuideDistance: .nan, decGuideDistance: .nan,
            raDuration: 0, decDuration: 0,
            xStep: nil, yStep: nil,
            starMass: 0, snr: 0, errorCode: 0,
            included: false, guiding: false,
            info: nil
        )
    }

    /// Use the first session's metadata as the canonical descriptor for the
    /// merged result — pixel scale, declination, and mount config are shared
    /// across a single observing setup, so the first session's values apply
    /// to the whole stitched timeline.
    private static func baseSession(from sorted: [GuideSession], startedAt: Date?) -> GuideSession {
        var merged = GuideSession()
        merged.startedAt = startedAt
        if let first = sorted.first {
            merged.pixelScale = first.pixelScale
            merged.declination = first.declination
            merged.mount = first.mount
            merged.ao = first.ao
            merged.rawHeader = first.rawHeader
        }
        // Suspect-data counts survive merging: a corrupt member session must
        // keep its warning visible on the merged night.
        merged.malformedFieldCount = sorted.reduce(0) { $0 + $1.malformedFieldCount }
        return merged
    }
}
