//
//  FrequencyAnalyzer.swift
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

import Accelerate
import Foundation

/// Frequency-domain analysis of a guide-session axis. Periods are in seconds
/// (the natural unit for diagnosing worm-drive harmonics).
nonisolated struct FrequencySpectrum: Sendable, Equatable {
    /// Periods in seconds, one per frequency bin (excluding DC).
    var periods: [Double]
    /// Magnitudes aligned with `periods`, normalised so peak == 1.
    var magnitudes: [Double]
    /// Period of the bin with the largest magnitude, or nil for a flat spectrum.
    var dominantPeriod: Double?
    /// Effective sample interval (seconds) used for the transform.
    var sampleInterval: Double
    /// Length of the zero-padded transform input (a power of 2).
    var sampleCount: Int
    /// Whether linear drift was removed before transforming.
    var driftCorrected: Bool
}

nonisolated enum FrequencyAxis: Sendable { case ra, dec }

nonisolated enum FrequencyAnalyzer {

    /// Compute the magnitude spectrum of the given axis.
    /// Returns `nil` if there are too few included frames or the timestamps don't form a valid interval.
    static func analyze(
        session: GuideSession,
        axis: FrequencyAxis = .ra,
        driftCorrect: Bool = true
    ) -> FrequencySpectrum? {
        let entries = session.entries.filter(\.included)
        guard entries.count >= 32 else { return nil }

        let values = entries.map { axis == .ra ? $0.raRawDistance : $0.decRawDistance }
        let times = entries.map(\.time)
        return analyze(values: values, times: times, driftCorrect: driftCorrect)
    }

    /// Pure-data variant — exposed for testing with synthetic signals.
    static func analyze(
        values: [Double],
        times: [Double],
        driftCorrect: Bool
    ) -> FrequencySpectrum? {
        guard values.count == times.count, values.count >= 32 else { return nil }
        guard let firstT = times.first, let lastT = times.last, lastT > firstT else { return nil }

        // Uniform sample interval = mean dt across the series.
        let dts = zip(times.dropFirst(), times).map { $0 - $1 }.filter { $0 > 0 }
        guard !dts.isEmpty else { return nil }
        let dt = dts.reduce(0, +) / Double(dts.count)
        guard dt > 0 else { return nil }

        let span = lastT - firstT
        let n = Int(span / dt) + 1
        guard n >= 32 else { return nil }

        let resampled = resample(values: values, times: times, n: n, dt: dt, t0: firstT)
        let detrended = driftCorrect ? subtractLinearTrend(resampled) : subtractMean(resampled)
        let windowed = applyHannWindow(detrended)

        let paddedN = nextPowerOfTwo(windowed.count)
        var padded = windowed
        padded.append(contentsOf: Array(repeating: 0, count: paddedN - windowed.count))

        let rawMags = realFFTMagnitudes(padded)

        // Map non-DC bins to periods. Bin i (i >= 1) corresponds to period = N*dt / i.
        var periods: [Double] = []
        var mags: [Double] = []
        for i in 1..<rawMags.count {
            periods.append(Double(paddedN) * dt / Double(i))
            mags.append(rawMags[i])
        }

        // Normalise so the largest magnitude is 1 — magnitudes are otherwise
        // scale-dependent and unhelpful as a Y-axis label.
        let peak = mags.max() ?? 1
        let normalised = peak > 0 ? mags.map { $0 / peak } : mags

        let dominant: Double? = {
            guard let idx = mags.firstIndex(of: peak), peak > 0 else { return nil }
            return periods[idx]
        }()

        return FrequencySpectrum(
            periods: periods,
            magnitudes: normalised,
            dominantPeriod: dominant,
            sampleInterval: dt,
            sampleCount: paddedN,
            driftCorrected: driftCorrect
        )
    }

    // MARK: - Pre-processing

    static func resample(values: [Double], times: [Double], n: Int, dt: Double, t0: Double) -> [Double] {
        var out = Array(repeating: 0.0, count: n)
        var j = 0
        let lastIdx = values.count - 1
        for i in 0..<n {
            let t = t0 + Double(i) * dt
            while j < lastIdx, times[j + 1] < t { j += 1 }
            if j >= lastIdx {
                out[i] = values[lastIdx]
            } else if t <= times[0] {
                out[i] = values[0]
            } else {
                let t0Seg = times[j]
                let t1Seg = times[j + 1]
                let segDt = t1Seg - t0Seg
                if segDt <= 0 {
                    out[i] = values[j]
                } else {
                    let alpha = (t - t0Seg) / segDt
                    out[i] = values[j] + alpha * (values[j + 1] - values[j])
                }
            }
        }
        return out
    }

    static func subtractLinearTrend(_ values: [Double]) -> [Double] {
        let n = values.count
        guard n >= 2 else { return values }
        let mx = Double(n - 1) / 2.0
        let my = values.reduce(0, +) / Double(n)
        var num = 0.0
        var den = 0.0
        for i in 0..<n {
            let dx = Double(i) - mx
            num += dx * (values[i] - my)
            den += dx * dx
        }
        let slope = den > 0 ? num / den : 0
        let intercept = my - slope * mx
        return values.enumerated().map { i, v in v - (slope * Double(i) + intercept) }
    }

    static func subtractMean(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return values }
        let m = values.reduce(0, +) / Double(values.count)
        return values.map { $0 - m }
    }

    static func applyHannWindow(_ values: [Double]) -> [Double] {
        let n = values.count
        guard n > 1 else { return values }
        let denom = Double(n - 1)
        return values.enumerated().map { i, v in
            let w = 0.5 - 0.5 * cos(2.0 * .pi * Double(i) / denom)
            return v * w
        }
    }

    static func nextPowerOfTwo(_ n: Int) -> Int {
        guard n > 0 else { return 1 }
        var p = 1
        while p < n { p <<= 1 }
        return p
    }

    // MARK: - vDSP real FFT

    /// Real FFT magnitudes using the standard split-complex packing trick.
    /// Input length must be a power of two; output length is `n / 2`.
    static func realFFTMagnitudes(_ input: [Double]) -> [Double] {
        let n = input.count
        precondition(n > 0 && (n & (n - 1)) == 0, "FFT length must be a power of two")
        let log2n = vDSP_Length(log2(Double(n)))
        let halfN = n / 2

        var realParts = Array(repeating: 0.0, count: halfN)
        var imagParts = Array(repeating: 0.0, count: halfN)
        var magnitudes = Array(repeating: 0.0, count: halfN)

        realParts.withUnsafeMutableBufferPointer { realPtr in
            imagParts.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPDoubleSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )

                input.withUnsafeBufferPointer { inPtr in
                    inPtr.baseAddress!.withMemoryRebound(to: DSPDoubleComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctozD(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                }

                guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return }
                defer { vDSP_destroy_fftsetupD(setup) }

                vDSP_fft_zripD(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                magnitudes.withUnsafeMutableBufferPointer { magPtr in
                    vDSP_zvabsD(&splitComplex, 1, magPtr.baseAddress!, 1, vDSP_Length(halfN))
                }
            }
        }

        return magnitudes
    }
}
