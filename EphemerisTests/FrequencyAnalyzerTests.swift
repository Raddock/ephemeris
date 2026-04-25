//
//  FrequencyAnalyzerTests.swift
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

struct FrequencyAnalyzerTests {

    @Test func recoversKnownSineWavePeriod() {
        // 60-second period, sampled every 5 seconds for 30 minutes (360 samples).
        let dt = 5.0
        let nSamples = 360
        let truePeriod = 60.0
        var values: [Double] = []
        var times: [Double] = []
        for i in 0..<nSamples {
            let t = Double(i) * dt
            times.append(t)
            values.append(sin(2.0 * .pi * t / truePeriod))
        }

        let spectrum = FrequencyAnalyzer.analyze(values: values, times: times, driftCorrect: false)
        #expect(spectrum != nil)
        guard let s = spectrum, let dom = s.dominantPeriod else {
            Issue.record("expected dominant period")
            return
        }
        // FFT bin resolution at this length is coarse; allow ±2.5 s tolerance.
        #expect(abs(dom - truePeriod) < 2.5)
    }

    @Test func driftRemovalSurfacesUnderlyingPeriod() {
        // 60 s sine plus a strong linear ramp. Without drift correction the
        // ramp's low-frequency leakage masks the sine. With correction, the
        // dominant period should be near 60 s.
        let dt = 5.0
        let nSamples = 360
        let truePeriod = 60.0
        var values: [Double] = []
        var times: [Double] = []
        for i in 0..<nSamples {
            let t = Double(i) * dt
            times.append(t)
            values.append(sin(2.0 * .pi * t / truePeriod) + 0.005 * t)
        }

        let corrected = FrequencyAnalyzer.analyze(values: values, times: times, driftCorrect: true)
        let raw = FrequencyAnalyzer.analyze(values: values, times: times, driftCorrect: false)
        #expect(corrected != nil)
        #expect(raw != nil)

        let dominantCorrected = corrected!.dominantPeriod ?? 0
        let dominantRaw = raw!.dominantPeriod ?? 0
        #expect(abs(dominantCorrected - truePeriod) < 2.5)
        // The undetrended dominant should be much longer (the ramp itself).
        #expect(dominantRaw > truePeriod * 3)
    }

    @Test func returnsNilForTooFewSamples() {
        let times = (0..<10).map { Double($0) * 5.0 }
        let values = times.map { sin(2.0 * .pi * $0 / 60.0) }
        #expect(FrequencyAnalyzer.analyze(values: values, times: times, driftCorrect: false) == nil)
    }

    @Test func resamplePreservesEndpoints() {
        let times: [Double] = [0, 1, 3, 7]
        let values: [Double] = [0, 10, 30, 70]
        let r = FrequencyAnalyzer.resample(values: values, times: times, n: 8, dt: 1.0, t0: 0)
        #expect(abs(r[0] - 0) < 1e-9)
        #expect(abs(r.last! - 70) < 1e-9)
    }

    @Test func subtractLinearTrendFlattensRamp() {
        let ramp = (0..<100).map { Double($0) * 0.5 + 5 }
        let detrended = FrequencyAnalyzer.subtractLinearTrend(ramp)
        // Residual should be near zero everywhere.
        let maxAbs = detrended.map(abs).max() ?? 0
        #expect(maxAbs < 1e-9)
    }

    @Test func nextPowerOfTwoIsCorrect() {
        #expect(FrequencyAnalyzer.nextPowerOfTwo(1) == 1)
        #expect(FrequencyAnalyzer.nextPowerOfTwo(2) == 2)
        #expect(FrequencyAnalyzer.nextPowerOfTwo(3) == 4)
        #expect(FrequencyAnalyzer.nextPowerOfTwo(255) == 256)
        #expect(FrequencyAnalyzer.nextPowerOfTwo(256) == 256)
        #expect(FrequencyAnalyzer.nextPowerOfTwo(257) == 512)
    }
}
