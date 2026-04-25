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
        for session in sorted {
            let offset = session.startedAt!.timeIntervalSince(baseDate)
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
        for session in sorted {
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
        return merged
    }
}
