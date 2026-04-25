//
//  AggregateStatsTests.swift
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
import Testing
@testable import Ephemeris

struct AggregateStatsTests {

    @Test func emptyLogProducesEmptyStats() {
        let stats = LogAggregateStatsCalculator.calculate(GuideLog())
        #expect(stats == .empty)
    }

    @Test func aggregatesFrameCountsAndDuration() {
        var log = GuideLog()
        log.guideSessions = [
            session(durationSec: 600, entries: makeEntries(count: 100, allIncluded: true)),
            session(durationSec: 1200, entries: makeEntries(count: 200, allIncluded: true)),
        ]
        let stats = LogAggregateStatsCalculator.calculate(log)
        #expect(stats.guideSessionCount == 2)
        #expect(stats.totalIncludedFrames == 300)
        #expect(stats.totalExcludedFrames == 0)
        #expect(stats.totalDurationSeconds == 1800)
    }

    @Test func weightedRMSCombinesByFrameCount() {
        // Two sessions with same per-axis RMS contribute proportionally to weighted RMS.
        // Synthesize sessions with constant noise — std-dev computed from the values.
        var log = GuideLog()
        let s1 = sessionWithRA(constants: [0.1, -0.1, 0.1, -0.1])  // RMS = 0.1
        let s2 = sessionWithRA(constants: [0.3, -0.3, 0.3, -0.3])  // RMS = 0.3
        log.guideSessions = [s1, s2]
        let stats = LogAggregateStatsCalculator.calculate(log)
        // weightedRMSRA² = (0.01 * 4 + 0.09 * 4) / 8 = 0.05  →  weightedRMSRA ≈ 0.2236
        #expect(abs(stats.weightedRMSRA - 0.05.squareRoot()) < 1e-9)
    }

    @Test func identifiesBestAndWorstSession() {
        var log = GuideLog()
        log.guideSessions = [
            sessionWithRA(constants: [0.5, -0.5, 0.5, -0.5]),  // RMS 0.5
            sessionWithRA(constants: [0.1, -0.1, 0.1, -0.1]),  // RMS 0.1 — best
            sessionWithRA(constants: [1.0, -1.0, 1.0, -1.0]),  // RMS 1.0 — worst
        ]
        let stats = LogAggregateStatsCalculator.calculate(log)
        #expect(stats.bestSessionIndex == 1)
        #expect(stats.worstSessionIndex == 2)
    }

    // MARK: - Builders

    private func session(durationSec: Double, entries: [GuideEntry]) -> GuideSession {
        var s = GuideSession()
        s.entries = entries
        // Force last entry's time to durationSec for `duration` accessor.
        if !s.entries.isEmpty {
            s.entries[s.entries.count - 1].time = durationSec
        }
        return s
    }

    private func sessionWithRA(constants: [Double]) -> GuideSession {
        var s = GuideSession()
        s.pixelScale = 1.0
        s.entries = constants.enumerated().map { i, v in
            GuideEntry(
                frame: i + 1, time: Double(i) + 1, deviceKind: .mount,
                dx: 0, dy: 0,
                raRawDistance: v, decRawDistance: 0,
                raGuideDistance: 0, decGuideDistance: 0,
                raDuration: 0, decDuration: 0,
                xStep: nil, yStep: nil,
                starMass: 0, snr: 0, errorCode: 0,
                included: true, guiding: true, info: nil
            )
        }
        return s
    }

    private func makeEntries(count: Int, allIncluded: Bool) -> [GuideEntry] {
        (0..<count).map { i in
            GuideEntry(
                frame: i + 1, time: Double(i) + 1, deviceKind: .mount,
                dx: 0, dy: 0,
                raRawDistance: 0, decRawDistance: 0,
                raGuideDistance: 0, decGuideDistance: 0,
                raDuration: 0, decDuration: 0,
                xStep: nil, yStep: nil,
                starMass: 0, snr: 0, errorCode: allIncluded ? 0 : 3,
                included: allIncluded, guiding: true, info: nil
            )
        }
    }
}
