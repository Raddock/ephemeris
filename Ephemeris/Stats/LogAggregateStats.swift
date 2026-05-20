//
//  LogAggregateStats.swift
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

/// File-level summary across every guide session in a `GuideLog`.
nonisolated struct LogAggregateStats: Sendable, Equatable {
    var guideSessionCount: Int = 0
    var calibrationCount: Int = 0
    var totalIncludedFrames: Int = 0
    var totalExcludedFrames: Int = 0
    var totalDurationSeconds: Double = 0

    /// Frame-count-weighted RMS across all sessions, in pixels.
    var weightedRMSRA: Double = 0
    var weightedRMSDec: Double = 0
    var weightedRMSTotal: Double = 0

    /// Pixel scale shared by all sessions, or 0 if mixed/unknown.
    /// (PHD2 logs from one observing system always share the same pixel scale.)
    var pixelScale: Double = 0

    /// Index into `log.guideSessions` — best by total RMS, worst by total RMS.
    var bestSessionIndex: Int?
    var worstSessionIndex: Int?

    var firstStarted: Date?
    var lastEnded: Date?

    static let empty = LogAggregateStats()
}

nonisolated enum LogAggregateStatsCalculator {

    static func calculate(_ log: GuideLog) -> LogAggregateStats {
        var agg = LogAggregateStats()
        agg.calibrationCount = log.calibrations.count

        var sumRASq = 0.0
        var sumDecSq = 0.0
        var totalIncluded = 0
        var bestRMS = Double.infinity
        var worstRMS = -Double.infinity
        var bestIdx: Int?
        var worstIdx: Int?
        var firstDate: Date?
        var lastDate: Date?
        var pixelScales = Set<Double>()

        for (i, session) in log.guideSessions.enumerated() {
            let s = SessionStatsCalculator.calculate(session)
            agg.guideSessionCount += 1
            agg.totalDurationSeconds += session.duration
            agg.totalIncludedFrames += s.includedFrames
            agg.totalExcludedFrames += s.excludedFrames

            if s.includedFrames > 0 {
                let n = Double(s.includedFrames)
                sumRASq += s.rmsRA * s.rmsRA * n
                sumDecSq += s.rmsDec * s.rmsDec * n
                totalIncluded += s.includedFrames

                if s.rmsTotal < bestRMS {
                    bestRMS = s.rmsTotal
                    bestIdx = i
                }
                if s.rmsTotal > worstRMS {
                    worstRMS = s.rmsTotal
                    worstIdx = i
                }
            }

            if let started = session.startedAt {
                if firstDate == nil || started < firstDate! { firstDate = started }
                let ended = started.addingTimeInterval(session.duration)
                if lastDate == nil || ended > lastDate! { lastDate = ended }
            }

            if session.pixelScale > 0 {
                pixelScales.insert(session.pixelScale)
            }
        }

        if totalIncluded > 0 {
            agg.weightedRMSRA = (sumRASq / Double(totalIncluded)).squareRoot()
            agg.weightedRMSDec = (sumDecSq / Double(totalIncluded)).squareRoot()
            agg.weightedRMSTotal = (agg.weightedRMSRA * agg.weightedRMSRA
                                    + agg.weightedRMSDec * agg.weightedRMSDec).squareRoot()
        }

        agg.bestSessionIndex = bestIdx
        agg.worstSessionIndex = worstIdx
        agg.firstStarted = firstDate
        agg.lastEnded = lastDate
        agg.pixelScale = pixelScales.count == 1 ? pixelScales.first! : 0

        return agg
    }
}
