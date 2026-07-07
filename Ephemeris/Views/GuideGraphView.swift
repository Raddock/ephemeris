//
//  GuideGraphView.swift
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

struct GuideGraphView: View {
    let session: GuideSession
    let chartState: ChartViewState
    @Binding var hoverTime: Double?
    let selectedTime: Double?
    @Binding var visibleDomain: ClosedRange<Double>?
    let fullDomain: ClosedRange<Double>
    @Binding var manualExclusions: [ClosedRange<Double>]

    @State private var dragRange: ClosedRange<Double>?
    @State private var lastDragRange: ClosedRange<Double>?
    @State private var chartCache: GuideChartData?

    private var raColor: Color { Color(nsColor: .systemRed) }
    private var decColor: Color { Color(nsColor: .systemBlue) }

    /// Live hover takes priority; falls back to a clicked/pinned selection.
    private var activeTime: Double? { hoverTime ?? selectedTime }
    private var isPinned: Bool { hoverTime == nil && selectedTime != nil }

    private var chartKey: GuideChartData.Key {
        GuideChartData.Key(sessionID: session.id,
                           axisMode: chartState.axisMode,
                           domainLo: visibleDomain?.lowerBound,
                           domainHi: visibleDomain?.upperBound)
    }

    /// The cached model, only if it matches the current key — a stale model from
    /// another session or zoom level renders nothing rather than wrong data.
    private var currentData: GuideChartData? {
        chartCache?.key == chartKey ? chartCache : nil
    }

    var body: some View {
        Group {
            if let data = currentData {
                chart(data)
            } else {
                Color.clear
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .task(id: chartKey) {
            chartCache = GuideChartData(session: session, key: chartKey)
        }
    }

    private func chart(_ data: GuideChartData) -> some View {
        Chart {
            if chartState.showEvents {
                settlingBandMarks(data)
            }

            manualExclusionMarks

            zeroBaseline

            if chartState.showCorrections, chartState.axisMode == .raDec {
                correctionBars(data)
            }

            if chartState.showRA {
                seriesLine(data.raPoints, name: "RA", color: raColor)
            }
            if chartState.showDec {
                seriesLine(data.decPoints, name: "Dec", color: decColor)
            }

            if chartState.showEvents {
                eventRules(data)
            }

            if let entry = activeEntry(in: data) {
                hoverMark(entry, pinned: isPinned)
            }

            if let r = dragRange {
                RectangleMark(
                    xStart: .value("Drag start", r.lowerBound),
                    xEnd: .value("Drag end", r.upperBound)
                )
                .foregroundStyle(dragHighlightColor)
            }
        }
        .chartXScale(domain: visibleDomain ?? fullDomain)
        .chartYScale(domain: yDomain(data))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                if chartState.showGrid {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.35))
                }
                AxisTick().foregroundStyle(.secondary.opacity(0.55))
                AxisValueLabel {
                    if let t = value.as(Double.self) {
                        Text(formatTime(t)).font(.caption)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 7)) { value in
                if chartState.showGrid {
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.35))
                }
                AxisTick().foregroundStyle(.secondary.opacity(0.55))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatY(v)).font(.caption)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
        .accessibilityLabel(chartState.units == .arcsec
            ? "Guide error over time, RA and declination in arc-seconds"
            : "Guide error over time, RA and declination in pixels")
        .overlay(alignment: .topLeading) {
            if chartState.showHoverCard, let entry = activeEntry(in: data) {
                HoverCard(entry: entry, session: session, chartState: chartState)
                    .padding(.leading, 56) // clear the leading Y-axis labels
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
        }
        .chartXSelection(value: $hoverTime)
        .chartXSelection(range: $dragRange)
        .onChange(of: dragRange) { old, new in
            if let new {
                lastDragRange = new
            } else if old != nil {
                // Drag finished — commit per current drag mode if it spans more than ~1s.
                if let last = lastDragRange, last.upperBound - last.lowerBound > 1.0 {
                    switch chartState.dragMode {
                    case .zoom:
                        visibleDomain = last
                    case .exclude:
                        manualExclusions.append(last)
                    }
                }
                lastDragRange = nil
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Marks

    private var zeroBaseline: some ChartContent {
        RuleMark(y: .value("Zero", 0.0))
            .foregroundStyle(.secondary.opacity(0.45))
            .lineStyle(StrokeStyle(lineWidth: 0.5))
    }

    private func seriesLine(_ points: [GuideChartData.SeriesPoint],
                            name: String, color: Color) -> some ChartContent {
        ForEach(points) { point in
            LineMark(
                x: .value("Time", point.time),
                y: .value(name, display(point.valuePx)),
                series: .value("Series", name)
            )
            .foregroundStyle(color)
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 2.0))
        }
    }

    @ChartContentBuilder
    private func correctionBars(_ data: GuideChartData) -> some ChartContent {
        ForEach(data.raCorrections) { point in
            BarMark(
                x: .value("Time", point.time),
                yStart: .value("Zero", 0),
                yEnd: .value("RA correction", display(point.valuePx))
            )
            .foregroundStyle(raColor.opacity(0.32))
        }
        ForEach(data.decCorrections) { point in
            BarMark(
                x: .value("Time", point.time),
                yStart: .value("Zero", 0),
                yEnd: .value("Dec correction", display(point.valuePx))
            )
            .foregroundStyle(decColor.opacity(0.32))
        }
    }

    private func eventRules(_ data: GuideChartData) -> some ChartContent {
        ForEach(data.eventMarkers) { marker in
            RuleMark(x: .value("Time", marker.time))
                .foregroundStyle(color(for: marker.kind))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private var manualExclusionMarks: some ChartContent {
        ForEach(manualExclusions.indices, id: \.self) { i in
            RectangleMark(
                xStart: .value("Excl start", manualExclusions[i].lowerBound),
                xEnd: .value("Excl end", manualExclusions[i].upperBound)
            )
            .foregroundStyle(Color(nsColor: .tertiaryLabelColor).opacity(0.55))
        }
    }

    private var dragHighlightColor: Color {
        switch chartState.dragMode {
        case .zoom:    return Color.accentColor.opacity(0.18)
        case .exclude: return Color(nsColor: .systemOrange).opacity(0.22)
        }
    }

    private func settlingBandMarks(_ data: GuideChartData) -> some ChartContent {
        ForEach(data.settlingBands) { band in
            RectangleMark(
                xStart: .value("Start", band.startTime),
                xEnd: .value("End", band.endTime)
            )
            .foregroundStyle(band.succeeded
                ? Color.secondary.opacity(0.14)
                : Color(nsColor: .systemOrange).opacity(0.18))
        }
    }

    @ChartContentBuilder
    private func hoverMark(_ entry: GuideEntry, pinned: Bool) -> some ChartContent {
        RuleMark(x: .value("Hover", entry.time))
            .foregroundStyle(pinned ? Color.accentColor.opacity(0.9) : .primary.opacity(0.45))
            .lineStyle(StrokeStyle(lineWidth: pinned ? 2 : 1.5))

        // Pinned state gets small filled dots at the data points so the
        // selection reads as "fixed" rather than "live cursor".
        if pinned {
            if chartState.showRA {
                PointMark(
                    x: .value("Pinned", entry.time),
                    y: .value("RA", display(rawX(entry)))
                )
                .symbolSize(60)
                .foregroundStyle(raColor)
            }
            if chartState.showDec {
                PointMark(
                    x: .value("Pinned", entry.time),
                    y: .value("Dec", display(rawY(entry)))
                )
                .symbolSize(60)
                .foregroundStyle(decColor)
            }
        }
    }


    // MARK: - Hover/selection lookup

    /// Nearest real entry to the hover/selection time. Sentinel entries are
    /// excluded (they're NaN), but parser-flagged frames stay findable — the
    /// hover card surfaces those via the orange "Excluded" badge.
    private func activeEntry(in data: GuideChartData) -> GuideEntry? {
        guard let t = activeTime else { return nil }
        return data.nearestRealEntry(to: t)
    }

    // MARK: - Data conversion

    /// Pre-correction RA distance, or `dx`, depending on axis mode.
    fileprivate func rawX(_ e: GuideEntry) -> Double {
        chartState.axisMode == .raDec ? e.raRawDistance : e.dx
    }
    fileprivate func rawY(_ e: GuideEntry) -> Double {
        chartState.axisMode == .raDec ? e.decRawDistance : e.dy
    }

    /// Convert a pixel value to the user-selected display units.
    fileprivate func display(_ valuePx: Double) -> Double {
        SessionStats.display(valuePx, as: chartState.units, pixelScale: session.pixelScale)
    }

    // MARK: - Domain

    /// Symmetric Y domain around zero. `.fixedArcsec` overrides; `.auto` pads 10%
    /// beyond the largest data magnitude inside the visible X domain. The
    /// magnitudes come precomputed from the chart model, so this is O(1) per
    /// render instead of a full-session scan.
    private func yDomain(_ data: GuideChartData) -> ClosedRange<Double> {
        if case .fixedArcsec(let arcsec) = chartState.yScale {
            // The domain values are always in the currently selected display units.
            let v: Double
            switch chartState.units {
            case .arcsec: v = arcsec
            case .pixels:
                let scale = session.pixelScale
                v = scale > 0 ? arcsec / scale : arcsec
            }
            return -v...v
        }
        var maxMagPx = data.maxSeriesMagnitudePx
        if chartState.showCorrections, chartState.axisMode == .raDec {
            maxMagPx = max(maxMagPx, data.maxCorrectionMagnitudePx)
        }
        var maxMag = abs(display(maxMagPx))
        if maxMag == 0 { maxMag = 1 }
        let padded = maxMag * 1.1
        return -padded...padded
    }

    // MARK: - Events

    private func color(for kind: InfoKind) -> Color {
        switch kind {
        case .dither: return Color(nsColor: .systemPurple).opacity(0.55)
        case .starLost, .frameDropped: return Color(nsColor: .systemOrange).opacity(0.55)
        case .calibrationRejected: return Color(nsColor: .systemRed).opacity(0.55)
        case .mountGeometryChange: return Color(nsColor: .systemTeal).opacity(0.55)
        default: return .secondary.opacity(0.35)
        }
    }

    // MARK: - Formatters

    fileprivate func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    fileprivate func formatY(_ value: Double) -> String {
        switch chartState.units {
        case .pixels:
            return String(format: "%.2f", value)
        case .arcsec:
            return String(format: "%.1f\"", value)
        }
    }
}

// MARK: - Hover card

private struct HoverCard: View {
    let entry: GuideEntry
    let session: GuideSession
    let chartState: ChartViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Frame \(entry.frame)")
                    .fontWeight(.medium)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(timeText)
                    .foregroundStyle(.secondary)
            }
            .font(.caption.monospacedDigit())

            HStack(spacing: 12) {
                axisLine(label: chartState.axisMode == .raDec ? "RA" : "dx",
                         value: chartState.axisMode == .raDec ? entry.raRawDistance : entry.dx,
                         color: Color(nsColor: .systemRed))
                axisLine(label: chartState.axisMode == .raDec ? "Dec" : "dy",
                         value: chartState.axisMode == .raDec ? entry.decRawDistance : entry.dy,
                         color: Color(nsColor: .systemBlue))
            }
            .font(.caption2.monospacedDigit())

            HStack(spacing: 12) {
                Text("SNR \(snrText)")
                if !entry.included {
                    Text("·").foregroundStyle(.tertiary)
                    Text("Excluded")
                        .foregroundStyle(Color(nsColor: .systemOrange))
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            if let info = nearbyInfoText {
                Text(info)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.separator, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .fixedSize()
    }

    private func axisLine(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
            Text(distanceText(value))
        }
    }

    private func distanceText(_ valuePx: Double) -> String {
        let v = SessionStats.display(valuePx, as: chartState.units, pixelScale: session.pixelScale)
        switch chartState.units {
        case .pixels: return String(format: "%+.2f px", v)
        case .arcsec: return String(format: "%+.2f\"", v)
        }
    }

    private var snrText: String {
        String(format: "%.1f", entry.snr)
    }

    private var timeText: String {
        let total = Int(entry.time.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// Surface an INFO entry near this frame so dither/settling spikes self-explain.
    private var nearbyInfoText: String? {
        let window = 2
        return session.infos.first { abs($0.frame - entry.frame) <= window }?.text
    }
}
