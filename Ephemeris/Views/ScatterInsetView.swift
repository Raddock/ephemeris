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

    @State private var cloudCache: ScatterCloud?

    private var cloudKey: ScatterCloud.Key {
        ScatterCloud.Key(sessionID: session.id,
                         axisMode: chartState.axisMode,
                         units: chartState.units,
                         domainLo: visibleDomain?.lowerBound,
                         domainHi: visibleDomain?.upperBound,
                         exclusions: manualExclusions)
    }

    /// Cached point cloud. Hover only moves the highlighted point, so the cloud
    /// itself is rebuilt on session/axis/zoom/exclusion changes, never per
    /// mouse-move tick (the old code re-filtered every entry on each hover).
    private var currentCloud: ScatterCloud? {
        cloudCache?.key == cloudKey ? cloudCache : nil
    }

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

            if let cloud = currentCloud {
                ForEach(cloud.points) { p in
                    PointMark(
                        x: .value("X", p.x),
                        y: .value("Y", p.y)
                    )
                    .symbol(.circle)
                    .symbolSize(14)
                    .foregroundStyle(Color(nsColor: .systemYellow).opacity(0.55))
                }

                if let active = activePoint(in: cloud) {
                    PointMark(
                        x: .value("X", active.x),
                        y: .value("Y", active.y)
                    )
                    .symbol(.circle)
                    .symbolSize(40)
                    .foregroundStyle(Color(nsColor: .systemGreen))
                }
            }
        }
        .task(id: cloudKey) {
            cloudCache = ScatterCloud(session: session, key: cloudKey)
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.35))
                AxisTick().foregroundStyle(.secondary.opacity(0.55))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(format(v)).font(.system(size: 9))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.35))
                AxisTick().foregroundStyle(.secondary.opacity(0.55))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(format(v)).font(.system(size: 9))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame {
                    let frame = geo[plotFrame]
                    Canvas { ctx, _ in
                        drawReferenceRings(in: ctx, plotFrame: frame, proxy: proxy)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            Text(unitsSuffix)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(2)
        }
    }

    // MARK: - Data

    private func activePoint(in cloud: ScatterCloud) -> (x: Double, y: Double)? {
        guard let t = activeTime else { return nil }
        return cloud.point(near: t)
    }

    private var domain: ClosedRange<Double> {
        var maxMag = currentCloud?.maxMagnitude ?? 0
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

    /// Concentric reference rings every 0.5 of the current display unit
    /// (arc-seconds or pixels), mirroring PHD2's scatter target overlay so the
    /// reader can read each point's distance from the lock position at a glance.
    private func drawReferenceRings(in ctx: GraphicsContext, plotFrame: CGRect, proxy: ChartProxy) {
        guard let centerXPos = proxy.position(forX: 0.0),
              let centerYPos = proxy.position(forY: 0.0) else { return }
        let center = CGPoint(
            x: plotFrame.minX + centerXPos,
            y: plotFrame.minY + centerYPos
        )
        let outer = max(abs(domain.lowerBound), abs(domain.upperBound))
        let strokeColor = GraphicsContext.Shading.color(.secondary.opacity(0.28))
        let labelColor = Color.secondary.opacity(0.6)

        var r = 0.5
        while r <= outer + 0.001 {
            guard let edgeX = proxy.position(forX: r) else { r += 0.5; continue }
            let pixelRadius = abs(edgeX - centerXPos)
            let rect = CGRect(
                x: center.x - pixelRadius,
                y: center.y - pixelRadius,
                width: pixelRadius * 2,
                height: pixelRadius * 2
            )
            ctx.stroke(
                Path(ellipseIn: rect),
                with: strokeColor,
                style: StrokeStyle(lineWidth: 0.5, dash: [3, 2])
            )
            // Label the ring on the right edge with its radius and unit suffix.
            let labelText = String(format: "%.1f%@", r, unitsSuffix)
            let label = Text(labelText)
                .font(.system(size: 8))
                .foregroundColor(labelColor)
            ctx.draw(label, at: CGPoint(x: center.x + pixelRadius - 2, y: center.y - 7), anchor: .trailing)
            r += 0.5
        }
    }
}

// MARK: - Cached point cloud

/// Precomputed scatter cloud. Filtering, unit scaling, and the point-count cap
/// happen once per (session, axis, zoom, exclusions) change; hover lookups are
/// a binary search. `maxMagnitude` is computed over every qualifying entry, not
/// just the sampled ones, so the plot domain doesn't shift with the sampling.
nonisolated struct ScatterCloud {
    struct Key: Equatable, Sendable {
        let sessionID: UUID
        let axisMode: ChartViewState.AxisMode
        let units: ChartViewState.Units
        let domainLo: Double?
        let domainHi: Double?
        let exclusions: [ClosedRange<Double>]
    }

    struct CloudPoint: Identifiable, Sendable {
        let id: Int
        let x: Double
        let y: Double
    }

    /// PointMark budget. A wander cloud reads identically at a few thousand
    /// points; uniform stride sampling preserves its shape and density.
    static let maxPoints = 2000

    let key: Key
    let points: [CloudPoint]
    let maxMagnitude: Double

    private let times: [Double]
    private let xs: [Double]
    private let ys: [Double]

    init(session: GuideSession, key: Key) {
        self.key = key
        let scale = key.units == .arcsec ? session.pixelScale : 1.0
        let raDec = (key.axisMode == .raDec)
        let domain: ClosedRange<Double>?
        if let lo = key.domainLo, let hi = key.domainHi, lo < hi {
            domain = lo...hi
        } else {
            domain = nil
        }

        var times: [Double] = []
        var xs: [Double] = []
        var ys: [Double] = []
        var maxMag = 0.0
        for e in session.entries {
            guard e.included else { continue }
            if let domain, !domain.contains(e.time) { continue }
            if key.exclusions.contains(where: { $0.contains(e.time) }) { continue }
            let x = (raDec ? e.raRawDistance : e.dx) * scale
            let y = (raDec ? e.decRawDistance : e.dy) * scale
            guard !x.isNaN, !y.isNaN else { continue }
            times.append(e.time)
            xs.append(x)
            ys.append(y)
            maxMag = max(maxMag, abs(x), abs(y))
        }
        self.times = times
        self.xs = xs
        self.ys = ys
        self.maxMagnitude = maxMag

        let stride = max(1, Int((Double(times.count) / Double(Self.maxPoints)).rounded(.up)))
        var sampled: [CloudPoint] = []
        sampled.reserveCapacity(times.count / stride + 1)
        var i = 0
        while i < times.count {
            sampled.append(CloudPoint(id: i, x: xs[i], y: ys[i]))
            i += stride
        }
        self.points = sampled
    }

    /// The qualifying point nearest to `t`, if within half a second — matching
    /// the old per-render "active" highlight semantics.
    func point(near t: Double) -> (x: Double, y: Double)? {
        guard !times.isEmpty else { return nil }
        var lo = 0
        var hi = times.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if times[mid] < t { lo = mid + 1 } else { hi = mid }
        }
        var best = lo
        if lo > 0, abs(times[lo - 1] - t) <= abs(times[lo] - t) {
            best = lo - 1
        }
        guard abs(times[best] - t) < 0.5 else { return nil }
        return (xs[best], ys[best])
    }
}
