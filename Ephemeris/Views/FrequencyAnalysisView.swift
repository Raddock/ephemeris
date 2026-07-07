//
//  FrequencyAnalysisView.swift
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

import Charts
import SwiftUI

struct FrequencyAnalysisView: View {
    let session: GuideSession
    @Environment(\.dismiss) private var dismiss

    @State private var driftCorrect = true
    @State private var axis: FrequencyAxis = .ra
    @State private var hoverPeriod: Double?
    @State private var spectrum: FrequencySpectrum?

    /// Inputs that require re-running the FFT. Hover is deliberately absent —
    /// recomputing the spectrum on every mouse-move tick was audit cruft.
    private struct SpectrumKey: Equatable {
        let sessionID: UUID
        let axis: FrequencyAxis
        let driftCorrect: Bool
    }

    private var spectrumKey: SpectrumKey {
        SpectrumKey(sessionID: session.id, axis: axis, driftCorrect: driftCorrect)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .task(id: spectrumKey) {
            spectrum = FrequencyAnalyzer.analyze(session: session, axis: axis, driftCorrect: driftCorrect)
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 420, idealHeight: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Frequency Analysis")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Identify worm-period harmonics in the guiding signal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Axis", selection: $axis) {
                Text("RA").tag(FrequencyAxis.ra)
                Text("Dec").tag(FrequencyAxis.dec)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Toggle("Drift corrected", isOn: $driftCorrect)
                .toggleStyle(.switch)
                .controlSize(.small)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Chart

    @ViewBuilder
    private var content: some View {
        if let spectrum {
            spectrumChart(spectrum)
        } else {
            ContentUnavailableView(
                "Not enough data",
                systemImage: "waveform.slash",
                description: Text("Need at least 32 included frames to compute a spectrum.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func spectrumChart(_ spectrum: FrequencySpectrum) -> some View {
        let points = zip(spectrum.periods, spectrum.magnitudes).map(SpectrumPoint.init)
        return Chart {
            ForEach(points) { p in
                LineMark(
                    x: .value("Period", p.period),
                    y: .value("Magnitude", p.magnitude)
                )
                .foregroundStyle(Color(nsColor: .systemBlue))
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2.0))
            }
            ForEach(points) { p in
                AreaMark(
                    x: .value("Period", p.period),
                    y: .value("Magnitude", p.magnitude)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .systemBlue).opacity(0.32),
                            Color(nsColor: .systemBlue).opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.linear)
            }
            if let dom = spectrum.dominantPeriod {
                RuleMark(x: .value("Dominant", dom))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            if let hp = hoverPeriod {
                RuleMark(x: .value("Hover", hp))
                    .foregroundStyle(.primary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXScale(domain: spectrum.xDomain, type: .log)
        .chartXAxis {
            AxisMarks(values: spectrum.xTickValues) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.35))
                AxisTick().foregroundStyle(.secondary.opacity(0.55))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatPeriod(v)).font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.35))
                AxisTick().foregroundStyle(.secondary.opacity(0.55))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(String(format: "%.2f", v)).font(.caption2)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .accessibilityLabel("Frequency spectrum of the guiding signal, magnitude by period in seconds")
        .accessibilityValue(spectrum.dominantPeriod.map { "Dominant period \(formatPeriod($0))" } ?? "No dominant period found")
        .chartXSelection(value: $hoverPeriod)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 24) {
            if let spectrum {
                if let dom = spectrum.dominantPeriod {
                    stat("Dominant period", value: formatPeriod(dom))
                }
                stat("Sample interval", value: String(format: "%.1f s", spectrum.sampleInterval))
                stat("Transform length", value: "\(spectrum.sampleCount)")
                if let hp = hoverPeriod, let mag = spectrum.magnitude(atPeriod: hp) {
                    Spacer()
                    stat("Cursor", value: "\(formatPeriod(hp)) · \(String(format: "%.2f", mag))")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
    }

    private func formatPeriod(_ seconds: Double) -> String {
        if seconds >= 600 { return String(format: "%.0f s", seconds) }
        if seconds >= 60  { return String(format: "%.1f s", seconds) }
        if seconds >= 10  { return String(format: "%.2f s", seconds) }
        return String(format: "%.3f s", seconds)
    }
}

private struct SpectrumPoint: Identifiable {
    var id: Double { period }
    var period: Double
    var magnitude: Double
}

private extension FrequencySpectrum {
    var xDomain: ClosedRange<Double> {
        let lo = periods.last ?? 1
        let hi = periods.first ?? lo + 1
        return max(lo, 0.01)...max(hi, lo + 0.01)
    }

    /// Logarithmic tick values matching the visible domain.
    var xTickValues: [Double] {
        let lo = xDomain.lowerBound
        let hi = xDomain.upperBound
        guard lo > 0, hi > lo else { return [] }
        let logLo = log10(lo)
        let logHi = log10(hi)
        let firstDecade = Int(ceil(logLo))
        let lastDecade  = Int(floor(logHi))
        guard firstDecade <= lastDecade else { return [lo, hi] }
        return (firstDecade...lastDecade).map { pow(10.0, Double($0)) }
    }

    /// Magnitude at the bin nearest the requested period.
    func magnitude(atPeriod p: Double) -> Double? {
        guard !periods.isEmpty else { return nil }
        var best = 0
        var bestDist = abs(periods[0] - p)
        for i in 1..<periods.count {
            let d = abs(periods[i] - p)
            if d < bestDist {
                bestDist = d
                best = i
            }
        }
        return magnitudes[best]
    }
}
