//
//  CalibrationGraphView.swift
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

struct CalibrationGraphView: View {
    let calibration: Calibration

    var body: some View {
        if calibration.entries.isEmpty {
            ContentUnavailableView(
                "No calibration steps",
                systemImage: "scope",
                description: Text("This calibration section had no recorded steps.")
            )
        } else {
            chart
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

            ForEach(legs) { leg in
                ForEach(Array(leg.entries.enumerated()), id: \.element.id) { idx, entry in
                    LineMark(
                        x: .value("dx", entry.dx),
                        y: .value("dy", entry.dy),
                        series: .value("Leg", leg.id)
                    )
                    .foregroundStyle(leg.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    PointMark(
                        x: .value("dx", entry.dx),
                        y: .value("dy", entry.dy)
                    )
                    .foregroundStyle(leg.color)
                    .symbolSize(idx == leg.entries.count - 1 ? 64 : 22)
                }

                if let last = leg.entries.last {
                    PointMark(
                        x: .value("dx", last.dx),
                        y: .value("dy", last.dy)
                    )
                    .symbolSize(0)
                    .annotation(position: leg.annotationPosition, spacing: 4) {
                        Text("\(leg.shortLabel)\(last.step)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(leg.color)
                    }
                }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: domain)
        .chartXAxis { axisMarks(label: "dx (px)") }
        .chartYAxis { axisMarks(label: "dy (px)", leading: true) }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame {
                    let frame = geo[plotFrame]
                    Canvas { ctx, _ in
                        drawRings(in: ctx, plotFrame: frame, proxy: proxy)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            legend
                .padding(.top, 8)
        }
    }

    /// Draws concentric reference rings around the origin so the reader can
    /// gauge step distances at a glance — matches the target-style overlay on
    /// the original phdlogview's calibration plot.
    private func drawRings(in ctx: GraphicsContext, plotFrame: CGRect, proxy: ChartProxy) {
        guard let centerX = proxy.position(forX: 0.0),
              let centerY = proxy.position(forY: 0.0) else { return }
        let center = CGPoint(
            x: plotFrame.minX + centerX,
            y: plotFrame.minY + centerY
        )
        let outer = max(abs(domain.lowerBound), abs(domain.upperBound))
        let radii = ringRadii(outer: outer)
        let strokeColor = GraphicsContext.Shading.color(.secondary.opacity(0.22))
        let labelColor = Color.secondary.opacity(0.55)
        for r in radii {
            guard let edgeX = proxy.position(forX: r) else { continue }
            let pixelRadius = abs(edgeX - centerX)
            let rect = CGRect(
                x: center.x - pixelRadius,
                y: center.y - pixelRadius,
                width: pixelRadius * 2,
                height: pixelRadius * 2
            )
            ctx.stroke(
                Path(ellipseIn: rect),
                with: strokeColor,
                style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
            )
            let label = Text(String(format: "%.0f", r))
                .font(.system(size: 9))
                .foregroundColor(labelColor)
            ctx.draw(label, at: CGPoint(x: center.x + pixelRadius - 2, y: center.y - 8), anchor: .trailing)
        }
    }

    /// Pick "nice" radii (1, 2, 5 × 10ⁿ) up to the outer domain so rings sit
    /// at readable round numbers regardless of the calibration's step size.
    private func ringRadii(outer: Double) -> [Double] {
        guard outer > 0 else { return [] }
        let rough = outer / 4
        let exp = floor(log10(rough))
        let base = pow(10, exp)
        let candidates: [Double] = [1, 2, 5, 10].map { $0 * base }
        let step = candidates.min(by: { abs($0 - rough) < abs($1 - rough) }) ?? rough
        var radii: [Double] = []
        var r = step
        while r <= outer * 1.001 {
            radii.append(r)
            r += step
        }
        return radii
    }

    private func axisMarks(label: String, leading: Bool = false) -> some AxisContent {
        AxisMarks(position: leading ? .leading : .bottom, values: .automatic(desiredCount: 7)) { value in
            AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
            AxisTick().foregroundStyle(.secondary.opacity(0.5))
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(String(format: "%.1f", v)).font(.caption2)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(legs) { leg in
                HStack(spacing: 6) {
                    Circle().fill(leg.color).frame(width: 8, height: 8)
                    Text(leg.legendLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.separator, lineWidth: 0.5))
    }

    // MARK: - Legs

    private struct Leg: Identifiable {
        let id: String
        let direction: CalibrationEntry.Direction
        let entries: [CalibrationEntry]
        let color: Color
        let shortLabel: String
        let legendLabel: String

        var annotationPosition: AnnotationPosition {
            guard let last = entries.last else { return .topTrailing }
            switch (last.dx >= 0, last.dy >= 0) {
            case (true, true):   return .topTrailing
            case (true, false):  return .bottomTrailing
            case (false, true):  return .topLeading
            case (false, false): return .bottomLeading
            }
        }
    }

    private var legs: [Leg] {
        let order: [CalibrationEntry.Direction] = [.west, .east, .north, .south, .backlash]
        let grouped = Dictionary(grouping: calibration.entries, by: \.direction)
        return order.compactMap { dir -> Leg? in
            guard let entries = grouped[dir], !entries.isEmpty else { return nil }
            let sorted = entries.sorted { $0.step < $1.step }
            return Leg(
                id: dir.rawValue,
                direction: dir,
                entries: sorted,
                color: color(for: dir),
                shortLabel: shortLabel(for: dir),
                legendLabel: legendLabel(for: dir)
            )
        }
    }

    private func color(for direction: CalibrationEntry.Direction) -> Color {
        switch direction {
        case .west, .east: return Color(nsColor: .systemRed)
        case .north, .south: return Color(nsColor: .systemBlue)
        case .backlash: return Color(nsColor: .systemOrange)
        }
    }

    private func shortLabel(for direction: CalibrationEntry.Direction) -> String {
        switch direction {
        case .west: return "W"
        case .east: return "E"
        case .north: return "N"
        case .south: return "S"
        case .backlash: return "B"
        }
    }

    private func legendLabel(for direction: CalibrationEntry.Direction) -> String {
        switch direction {
        case .west: return "West"
        case .east: return "East"
        case .north: return "North"
        case .south: return "South"
        case .backlash: return "Backlash"
        }
    }

    // MARK: - Domain

    private var domain: ClosedRange<Double> {
        var maxMag = 0.0
        for e in calibration.entries {
            maxMag = max(maxMag, abs(e.dx), abs(e.dy))
        }
        if maxMag == 0 { maxMag = 1 }
        let padded = maxMag * 1.15
        return -padded...padded
    }
}
