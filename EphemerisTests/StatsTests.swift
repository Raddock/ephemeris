//
//  StatsTests.swift
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

struct StatsTests {

    // MARK: - Pure-function tests

    @Test func meanOfEmptyIsZero() {
        #expect(SessionStatsCalculator.mean([]) == 0)
    }

    @Test func standardDeviationOfConstantIsZero() {
        #expect(SessionStatsCalculator.standardDeviation([3, 3, 3, 3]) == 0)
    }

    @Test func standardDeviationKnownSequence() {
        // values 1,2,3,4,5 → mean 3, sumSq = 4+1+0+1+4 = 10, /5 = 2, sqrt = √2
        let s = SessionStatsCalculator.standardDeviation([1, 2, 3, 4, 5])
        #expect(abs(s - 2.0.squareRoot()) < 1e-9)
    }

    @Test func linearSlopePerfectRamp() {
        let x = [0.0, 1.0, 2.0, 3.0, 4.0]
        let y = [0.0, 2.0, 4.0, 6.0, 8.0]   // slope = 2
        let slope = SessionStatsCalculator.linearSlope(x: x, y: y)
        #expect(slope != nil)
        #expect(abs((slope ?? 0) - 2.0) < 1e-9)
    }

    @Test func linearSlopeFlatLineIsZero() {
        let slope = SessionStatsCalculator.linearSlope(x: [0, 1, 2, 3], y: [5, 5, 5, 5])
        #expect(slope == 0)
    }

    @Test func linearSlopeReturnsNilForZeroVariance() {
        let slope = SessionStatsCalculator.linearSlope(x: [1, 1, 1], y: [2, 3, 4])
        #expect(slope == nil)
    }

    @Test func polarAlignKönigAtEquator() {
        // 1 px/min drift, pixelScale 1.0 "/px, dec 0 → 1 arcsec/min drift → 3.82 arcmin
        let pa = SessionStatsCalculator.polarAlignErrorArcmin(
            driftDecPxPerMin: 1.0, pixelScale: 1.0, declinationRad: 0
        )
        #expect(pa != nil)
        #expect(abs((pa ?? 0) - 3.82) < 1e-9)
    }

    @Test func polarAlignAccountsForDeclination() {
        // At dec=60°, cos=0.5 → PA doubles for the same drift.
        let dec60 = SessionStatsCalculator.polarAlignErrorArcmin(
            driftDecPxPerMin: 1.0, pixelScale: 1.0, declinationRad: 60.0 * .pi / 180.0
        )
        #expect(dec60 != nil)
        #expect(abs((dec60 ?? 0) - (3.82 / 0.5)) < 1e-6)
    }

    @Test func polarAlignNilNearPole() {
        let pa = SessionStatsCalculator.polarAlignErrorArcmin(
            driftDecPxPerMin: 1.0, pixelScale: 1.0, declinationRad: 89.0 * .pi / 180.0
        )
        #expect(pa == nil)
    }

    // MARK: - Session-level tests

    @Test func emptySessionReturnsEmptyStats() {
        let s = GuideSession()
        let stats = SessionStatsCalculator.calculate(s)
        #expect(stats == .empty)
    }

    @Test func allExcludedSessionReturnsZeroIncluded() {
        var s = GuideSession()
        s.entries = [
            entry(frame: 1, time: 1, raRaw: 0.5, decRaw: -0.2, included: false),
            entry(frame: 2, time: 2, raRaw: 0.6, decRaw: -0.1, included: false),
        ]
        let stats = SessionStatsCalculator.calculate(s)
        #expect(stats.includedFrames == 0)
        #expect(stats.excludedFrames == 2)
        #expect(stats.rmsTotal == 0)
    }

    @Test func excludesDroppedFramesFromStats() {
        var s = GuideSession()
        s.pixelScale = 1.0
        // included: ra const 1.0; excluded: extreme outlier that would dominate RMS
        s.entries = [
            entry(frame: 1, time: 1, raRaw: 1.0, decRaw: 0, included: true),
            entry(frame: 2, time: 2, raRaw: 1.0, decRaw: 0, included: true),
            entry(frame: 3, time: 3, raRaw: 999.0, decRaw: 999, included: false),
            entry(frame: 4, time: 4, raRaw: 1.0, decRaw: 0, included: true),
        ]
        let stats = SessionStatsCalculator.calculate(s)
        #expect(stats.includedFrames == 3)
        #expect(stats.excludedFrames == 1)
        #expect(stats.rmsRA == 0)
        #expect(stats.peakRA == 0)
    }

    @Test func driftMatchesKnownSlope() {
        var s = GuideSession()
        s.pixelScale = 1.0
        s.declination = 0
        // dec increases by 0.5 px every 60 seconds → 0.5 px/min
        s.entries = (0..<10).map { i in
            entry(
                frame: i + 1,
                time: Double(i) * 60,
                raRaw: 0,
                decRaw: Double(i) * 0.5,
                included: true
            )
        }
        let stats = SessionStatsCalculator.calculate(s)
        #expect(abs(stats.driftDec - 0.5) < 1e-9)
        #expect(abs(stats.driftRA) < 1e-9)
        // PA ≈ 3.82 × 0.5 / cos(0) = 1.91 arcmin
        #expect(stats.polarAlignErrorArcmin != nil)
        #expect(abs((stats.polarAlignErrorArcmin ?? 0) - 1.91) < 1e-6)
    }

    @Test func bundledFixtureProducesPlausibleStats() throws {
        let bundle = Bundle(for: FixtureAnchorStats.self)
        let url = try #require(
            bundle.url(forResource: "sample_short", withExtension: "txt", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "sample_short", withExtension: "txt"),
            "sample_short.txt fixture must be bundled"
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        let log = GuideLogParser.parse(text)
        guard let session = log.guideSessions.first else {
            Issue.record("expected at least one guide session in fixture")
            return
        }
        let stats = SessionStatsCalculator.calculate(session)
        #expect(stats.includedFrames > 0)
        // Sanity: RMS values should be finite, non-negative, and small (< 50 px).
        #expect(stats.rmsRA >= 0 && stats.rmsRA < 50)
        #expect(stats.rmsDec >= 0 && stats.rmsDec < 50)
        #expect(stats.rmsTotal >= max(stats.rmsRA, stats.rmsDec) - 1e-9)
    }

    // MARK: - Helpers

    private func entry(
        frame: Int, time: Double, raRaw: Double, decRaw: Double, included: Bool
    ) -> GuideEntry {
        GuideEntry(
            frame: frame, time: time, deviceKind: .mount,
            dx: 0, dy: 0,
            raRawDistance: raRaw, decRawDistance: decRaw,
            raGuideDistance: 0, decGuideDistance: 0,
            raDuration: 0, decDuration: 0,
            xStep: nil, yStep: nil,
            starMass: 0, snr: 0, errorCode: included ? 0 : 3,
            included: included, guiding: true,
            info: nil
        )
    }
}

private final class FixtureAnchorStats {}
