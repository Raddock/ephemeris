//
//  ScatterInsetView.swift
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

/// Square XY scatter showing the cluster of guide-star deviations across the
/// session. Mirrors the inset on the original phdlogview's main chart so the
/// reader can see the shape of the wander pattern (drift, backlash spikes,
/// elongation) at a glance.
struct ScatterInsetView: View {
    let session: GuideSession
    let chartState: ChartViewState
    let activeTime: Double?
    let visibleDomain: ClosedRange<Double>?
    let manualExclusions: [ClosedRange<Double>]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer(minLength: 0)
            }
            chart
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator.opacity(0.6), lineWidth: 0.5)
        )
        .opacity(0.92)
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .frame(width: 220)
    }

    private var title: String {
        switch chartState.axisMode {
        case .raDec: return "RA / Dec scatter"
        case .dxDy:  return "dx / dy scatter"
        }
    }

    private var chart: some View {
        Chart {
            RuleMark(x: .value("Origin", 0))
                .foregroundStyle(.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
            RuleMark(y: .value("Origin", 0))
                .foregroundStyle(.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 0.5))

            ForEach(points) { p in
                PointMark(
                    x: .value("X", p.x),
                    y: .value("Y", p.y)
                )
                .symbol(.circle)
                .symbolSize(p.active ? 28 : 14)
                .foregroundStyle(p.active ? Color(nsColor: .systemYellow)
                                          : Color(nsColor: .systemYellow).opacity(0.55))
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisTick().foregroundStyle(.secondary.opacity(0.4))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(format(v)).font(.system(size: 9))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisTick().foregroundStyle(.secondary.opacity(0.4))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(format(v)).font(.system(size: 9))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            Text(unitsSuffix)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(2)
        }
    }

    // MARK: - Data

    private struct ScatterPoint: Identifiable {
        let id: Int
        let x: Double
        let y: Double
        let active: Bool
    }

    private var points: [ScatterPoint] {
        let scale = chartState.units == .arcsec ? session.pixelScale : 1.0
        let active = activeTime
        return session.entries.compactMap { e -> ScatterPoint? in
            guard e.included else { return nil }
            if let dom = visibleDomain, !dom.contains(e.time) { return nil }
            if manualExclusions.contains(where: { $0.contains(e.time) }) { return nil }

            let xRaw: Double
            let yRaw: Double
            switch chartState.axisMode {
            case .raDec:
                xRaw = e.raRawDistance
                yRaw = e.decRawDistance
            case .dxDy:
                xRaw = e.dx
                yRaw = e.dy
            }
            let isActive: Bool
            if let t = active {
                isActive = abs(e.time - t) < 0.5
            } else {
                isActive = false
            }
            return ScatterPoint(id: e.frame, x: xRaw * scale, y: yRaw * scale, active: isActive)
        }
    }

    private var domain: ClosedRange<Double> {
        var maxMag = 0.0
        for p in points {
            maxMag = max(maxMag, abs(p.x), abs(p.y))
        }
        if maxMag == 0 { maxMag = 1 }
        let padded = maxMag * 1.1
        return -padded...padded
    }

    private var unitsSuffix: String {
        switch chartState.units {
        case .pixels: return "px"
        case .arcsec: return "\""
        }
    }

    private func format(_ v: Double) -> String {
        switch chartState.units {
        case .pixels: return String(format: "%.1f", v)
        case .arcsec: return String(format: "%.1f", v)
        }
    }
}
