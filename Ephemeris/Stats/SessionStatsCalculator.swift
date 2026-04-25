//
//  SessionStatsCalculator.swift
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

enum SessionStatsCalculator {

    /// Compute summary stats for a guide session using its raw (pre-algorithm) distances.
    /// `manualExclusionRanges` removes additional frames whose `time` falls within any range.
    static func calculate(
        _ session: GuideSession,
        manualExclusionRanges: [ClosedRange<Double>] = []
    ) -> SessionStats {
        let included = session.entries.filter { entry in
            guard entry.included else { return false }
            for r in manualExclusionRanges where r.contains(entry.time) { return false }
            return true
        }
        guard !included.isEmpty else {
            var s = SessionStats.empty
            s.excludedFrames = session.entries.count
            return s
        }

        let ra = included.map(\.raRawDistance)
        let dec = included.map(\.decRawDistance)
        let times = included.map(\.time)

        let meanRA = mean(ra)
        let meanDec = mean(dec)

        let rmsRA = standardDeviation(ra, mean: meanRA)
        let rmsDec = standardDeviation(dec, mean: meanDec)
        let rmsTotal = (rmsRA * rmsRA + rmsDec * rmsDec).squareRoot()

        let peakRA = ra.lazy.map { abs($0 - meanRA) }.max() ?? 0
        let peakDec = dec.lazy.map { abs($0 - meanDec) }.max() ?? 0

        let driftRApxPerSec = linearSlope(x: times, y: ra) ?? 0
        let driftDecPxPerSec = linearSlope(x: times, y: dec) ?? 0
        let driftRApxPerMin = driftRApxPerSec * 60
        let driftDecPxPerMin = driftDecPxPerSec * 60

        let polar = polarAlignErrorArcmin(
            driftDecPxPerMin: driftDecPxPerMin,
            pixelScale: session.pixelScale,
            declinationRad: session.declination
        )

        return SessionStats(
            includedFrames: included.count,
            excludedFrames: session.entries.count - included.count,
            rmsRA: rmsRA, rmsDec: rmsDec, rmsTotal: rmsTotal,
            peakRA: peakRA, peakDec: peakDec,
            driftRA: driftRApxPerMin, driftDec: driftDecPxPerMin,
            polarAlignErrorArcmin: polar
        )
    }

    // MARK: - Pure helpers

    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Population standard deviation (RMS of residuals around the mean).
    static func standardDeviation(_ values: [Double]) -> Double {
        standardDeviation(values, mean: mean(values))
    }

    static func standardDeviation(_ values: [Double], mean m: Double) -> Double {
        guard values.count > 1 else { return 0 }
        var sumSq = 0.0
        for v in values {
            let d = v - m
            sumSq += d * d
        }
        return (sumSq / Double(values.count)).squareRoot()
    }

    /// Least-squares linear regression slope of y vs x. Returns `nil` when the
    /// x-variance is zero (e.g. all timestamps identical) or fewer than 2 samples.
    static func linearSlope(x: [Double], y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let mx = mean(x), my = mean(y)
        var num = 0.0, den = 0.0
        for i in 0..<x.count {
            let dx = x[i] - mx
            num += dx * (y[i] - my)
            den += dx * dx
        }
        guard den > 0 else { return nil }
        return num / den
    }

    /// König drift-method approximation:
    /// `PA_arcmin ≈ 3.82 × |drift_dec_arcsec_per_min| / cos(δ)`
    ///
    /// Returns `nil` when the target is within 5° of the celestial pole, where
    /// the small-angle approximation breaks down.
    static func polarAlignErrorArcmin(
        driftDecPxPerMin: Double,
        pixelScale: Double,
        declinationRad: Double
    ) -> Double? {
        let cosDec = abs(cos(declinationRad))
        let cosCutoff = cos(85.0 * .pi / 180.0)
        guard cosDec >= cosCutoff else { return nil }
        let driftArcsecPerMin = driftDecPxPerMin * pixelScale
        return abs(3.82 * driftArcsecPerMin / cosDec)
    }
}
