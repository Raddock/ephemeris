//
//  DiagnosticGraphView.swift
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

struct DiagnosticGraphView: View {
    enum Kind {
        case starMass, snr

        var label: String {
            switch self {
            case .starMass: return "Star mass"
            case .snr:      return "SNR"
            }
        }

        var color: Color {
            switch self {
            case .starMass: return Color(nsColor: .systemYellow)
            case .snr:      return Color(nsColor: .systemGreen)
            }
        }
    }

    let session: GuideSession
    let kind: Kind
    @Binding var hoverTime: Double?
    let activeTime: Double?
    let visibleDomain: ClosedRange<Double>

    /// Skip boundary sentinels from `GuideSessionMerger`. Their `starMass`
    /// and `snr` are zero (not NaN), so without filtering the line drops to
    /// zero and back at every session boundary, producing a sharp V-dip.
    private var realEntries: [GuideEntry] {
        session.entries.filter { !$0.raRawDistance.isNaN }
    }

    var body: some View {
        Chart {
            ForEach(realEntries) { entry in
                LineMark(
                    x: .value("Time", entry.time),
                    y: .value(kind.label, value(for: entry))
                )
                .foregroundStyle(kind.color)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
            }

            if let t = activeTime {
                RuleMark(x: .value("Active", t))
                    .foregroundStyle(.primary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXScale(domain: visibleDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.35))
                AxisTick().foregroundStyle(.secondary.opacity(0.55))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(yLabel(v)).font(.caption2)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $hoverTime)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Circle().fill(kind.color).frame(width: 6, height: 6)
                Text(label)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 22)
            .padding(.top, 4)
        }
    }

    private var label: String {
        if let entry = activeEntry {
            return "\(kind.label): \(formattedValue(value(for: entry)))"
        }
        return kind.label
    }

    private var activeEntry: GuideEntry? {
        guard let t = activeTime, !realEntries.isEmpty else { return nil }
        return realEntries.min { abs($0.time - t) < abs($1.time - t) }
    }

    private func value(for entry: GuideEntry) -> Double {
        switch kind {
        case .starMass: return Double(entry.starMass)
        case .snr:      return entry.snr
        }
    }

    private func yLabel(_ v: Double) -> String {
        switch kind {
        case .starMass:
            if abs(v) >= 10_000 { return String(format: "%.0fk", v / 1000) }
            return String(format: "%.0f", v)
        case .snr:
            return String(format: "%.0f", v)
        }
    }

    private func formattedValue(_ v: Double) -> String {
        switch kind {
        case .starMass:
            if abs(v) >= 10_000 { return String(format: "%.1fk", v / 1000) }
            return String(format: "%.0f", v)
        case .snr:
            return String(format: "%.1f", v)
        }
    }

}
