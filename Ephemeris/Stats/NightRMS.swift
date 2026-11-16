//
//  NightRMS.swift
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

/// The one definition of a night's RMS, shared by the Library ingestor (stored
/// on `NightRecordEntity.medianRMSArcsec`) and the single-night recommender, so
/// the document window and the Library chip judge a night by the same number.
nonisolated enum NightRMS {

    /// One guiding session's contribution: its total RMS in arcsec (already
    /// converted with that session's own pixel scale) and its included frames.
    struct Session: Sendable {
        let rmsArcsec: Double
        let frames: Int
    }

    /// Frame-weighted median of per-session RMS: half of the night's guided
    /// frames came from sessions at or below this value.
    ///
    /// A median, not a mean, so a few minutes of runaway (a mount that stopped
    /// tracking, a star dragged off before "Star lost") can't stand in for a
    /// night of good guiding. A weighted mean of squares put one such ASIAir
    /// night at 107″ when most of its guiding was under 1″; this gives 0.79″.
    /// Weighting by frames keeps a 12-second failed start from counting as much
    /// as an hour-long session. The worst-session figure still shows the
    /// failures; this number describes the typical guiding.
    ///
    /// Sessions with no included frames carry no weight. When the cumulative
    /// weight lands exactly on half, the two straddling sessions are averaged.
    static func frameWeightedMedian(_ sessions: [Session]) -> Double {
        let weighted = sessions
            .filter { $0.frames > 0 && $0.rmsArcsec.isFinite }
            .sorted { $0.rmsArcsec < $1.rmsArcsec }
        let total = weighted.reduce(0) { $0 + $1.frames }
        guard total > 0 else { return 0 }

        var cumulative = 0
        for (index, session) in weighted.enumerated() {
            cumulative += session.frames
            if cumulative * 2 == total, index + 1 < weighted.count {
                return (session.rmsArcsec + weighted[index + 1].rmsArcsec) / 2
            }
            if cumulative * 2 >= total {
                return session.rmsArcsec
            }
        }
        return weighted.last?.rmsArcsec ?? 0
    }
}
