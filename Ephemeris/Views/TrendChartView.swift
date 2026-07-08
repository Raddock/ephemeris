import SwiftUI
import Charts

/// Multi-night trend chart per design doc §7.3.
///
/// - X-axis: per-night data points
/// - Y-axis: per-night RMS in arcseconds (frame-weighted across the night)
/// - Imaging-scale reference line (the rig's imaging pixel scale) when configured
/// - Annotation markers as vertical dashed RuleMarks
/// - Three-tier verdict colors per point (sub-pixel / at-resolution / over-resolution)
///
/// Performance budget (§7.3): vectorized LinePlot/PointPlot only, no per-point
/// SwiftUI annotation views, max ~50 inline RuleMarks before clustering. At Phase 7
/// volumes (<200 nights typical) this is comfortably within budget.
struct TrendChartView: View {
    let nights: [NightSummary]
    let imagingPixelScale: Double  // 0 = not configured
    let annotations: [AnnotationMarker]
    /// When set, dragging across the chart selects a date interval and hands it
    /// up on release — the library adopts it as a custom range, mirroring the
    /// document window's drag-to-zoom.
    var onRangeSelected: ((ClosedRange<Date>) -> Void)? = nil

    @State private var dragRange: ClosedRange<Date>?
    @State private var lastDragRange: ClosedRange<Date>?

    private var rmsDistribution: [Double] {
        nights.map { $0.nightRMSArcsec }
    }

    /// One point per *observing* night. Multi-log nights (PHD2 splits a single
    /// observing run when it's restarted mid-session) collapse into a single
    /// time-weighted RMS so the trend curve doesn't pivot around two
    /// data points sharing the same x value — that produced a sharp
    /// area-fill triangle when monotone interpolation hit a vertical segment.
    ///
    /// Bucketing is noon-to-noon, not civil midnight: a restart at 00:10 belongs
    /// to the previous evening's run, and yesterday's 04:00 pre-dawn session is a
    /// different night from tonight's 22:00 session even though they share a date.
    private var chartPoints: [NightSummary] {
        let buckets = Dictionary(grouping: nights) {
            Self.observingNightStart(for: $0.nightDate)
        }
        let merged: [NightSummary] = buckets.map { day, group in
            let totalMin = group.reduce(0.0) { $0 + $1.totalIntegrationMinutes }
            let weightedRMS: Double
            if totalMin > 0 {
                weightedRMS = group.reduce(0.0) {
                    $0 + $1.nightRMSArcsec * $1.totalIntegrationMinutes
                } / totalMin
            } else {
                let vals = group.map { $0.nightRMSArcsec }.sorted()
                weightedRMS = vals[vals.count / 2]
            }
            let best = group.map { $0.bestSessionRMSArcsec }.filter { $0 > 0 }.min() ?? 0
            let worst = group.map { $0.worstSessionRMSArcsec }.max() ?? 0
            return NightSummary(
                id: group.first?.id ?? UUID(),
                nightDate: day,
                sessionsCount: group.reduce(0) { $0 + $1.sessionsCount },
                totalIntegrationMinutes: totalMin,
                nightRMSArcsec: weightedRMS,
                bestSessionRMSArcsec: best,
                worstSessionRMSArcsec: worst,
                calibrationOrthogonalityDeg: nil,
                guidingAssistantRan: group.contains { $0.guidingAssistantRan },
                subQuality: group.compactMap { $0.subQuality }.first
            )
        }
        return merged.sorted { $0.nightDate < $1.nightDate }
    }

    /// Calendar day (midnight) of the evening this observing night began —
    /// timestamps before local noon roll back to the previous day.
    private static func observingNightStart(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date.addingTimeInterval(-12 * 3600))
    }

    struct AnnotationMarker: Sendable, Identifiable {
        let id: UUID
        let date: Date
        let label: String
        init(id: UUID = UUID(), date: Date, label: String) {
            self.id = id; self.date = date; self.label = label
        }
    }

    var body: some View {
        if nights.isEmpty {
            ContentUnavailableView(
                "No trend data yet",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Open a PHD2 guide log so this rig has at least one night to plot.")
            )
            .frame(height: 280)
        } else {
            chartContent
        }
    }

    private var chartContent: some View {
        Chart {
            // Area gradient under the curve — soft visual weight without competing with points.
            // Monotone interpolation (not catmullRom) so the curve can't overshoot above the
            // data at chart boundaries — Catmull-Rom needs phantom control points at the edges
            // and was generating a vertical wedge artifact at the leftmost point.
            ForEach(chartPoints) { night in
                AreaMark(
                    x: .value("Night", night.nightDate),
                    y: .value("RMS", night.nightRMSArcsec)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor.opacity(0.25), .accentColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // Imaging-scale reference line (or rig-relative median if imaging not configured)
            if imagingPixelScale > 0 {
                RuleMark(y: .value("Imaging scale", imagingPixelScale))
                    .foregroundStyle(Color.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Imaging scale \(String(format: "%.2f″", imagingPixelScale))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.regularMaterial, in: Capsule())
                    }
            }

            // RMS line — accent color for visual continuity. Monotone matches the AreaMark
            // so they don't separate at the boundaries.
            ForEach(chartPoints) { night in
                LineMark(
                    x: .value("Night", night.nightDate),
                    y: .value("RMS", night.nightRMSArcsec)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            // Verdict-colored point markers
            ForEach(chartPoints) { night in
                let verdict = NightVerdictCalculator.verdict(
                    rmsArcsec: night.nightRMSArcsec,
                    imagingPixelScale: imagingPixelScale,
                    rigDistribution: rmsDistribution
                )
                PointMark(
                    x: .value("Night", night.nightDate),
                    y: .value("RMS", night.nightRMSArcsec)
                )
                .foregroundStyle(verdict.tint)
                .symbolSize(56)
                .symbol {
                    Circle()
                        .fill(verdict.tint)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 0.5))
                }
            }

            // Annotation markers
            ForEach(annotations.prefix(50)) { marker in
                RuleMark(x: .value("Annotation", marker.date))
                    .foregroundStyle(.blue.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // Live drag highlight while selecting a zoom window.
            if let r = dragRange {
                RectangleMark(
                    xStart: .value("Drag start", r.lowerBound),
                    xEnd: .value("Drag end", r.upperBound)
                )
                .foregroundStyle(Color.accentColor.opacity(0.18))
            }
        }
        .chartXSelection(range: $dragRange)
        .onChange(of: dragRange) { old, new in
            if let new {
                lastDragRange = new
            } else if old != nil {
                // Drag finished — hand the interval up if it spans at least half
                // a day (a click or micro-drag shouldn't hijack the range).
                if let last = lastDragRange, let onRangeSelected,
                   last.upperBound.timeIntervalSince(last.lowerBound) > 12 * 3600 {
                    onRangeSelected(last)
                }
                lastDragRange = nil
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, suggestedXStride))) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                AxisTick()
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                if let v = value.as(Double.self) {
                    AxisValueLabel { Text(String(format: "%.1f", v)) }
                }
                AxisGridLine()
            }
        }
        .chartYAxisLabel(position: .leading, alignment: .center, spacing: 4) {
            Text("Night RMS (″)").font(.caption)
        }
        .accessibilityLabel("Guiding error trend, one point per night, RMS in arc-seconds")
        .accessibilityValue("\(nights.count) night\(nights.count == 1 ? "" : "s") plotted")
        .frame(height: 280)
        .padding(.vertical, 8)
    }

    /// Adaptive X-axis stride so labels stay legible across Week → All ranges.
    private var suggestedXStride: Int {
        let firstDate = nights.first?.nightDate ?? .now
        let lastDate = nights.last?.nightDate ?? .now
        let days = max(1, Int(lastDate.timeIntervalSince(firstDate) / 86400))
        if days <= 14 { return 1 }
        if days <= 60 { return 7 }
        if days <= 180 { return 14 }
        return 30
    }
}

#Preview {
    TrendChartView(
        nights: (0..<14).map { i in
            NightSummary(
                nightDate: Date(timeIntervalSince1970: 1_750_000_000).addingTimeInterval(Double(i) * 86400),
                nightRMSArcsec: 0.3 + Double(i) * 0.05
            )
        },
        imagingPixelScale: 0.62,
        annotations: [
            .init(date: Date(timeIntervalSince1970: 1_750_000_000 + 7 * 86400), label: "OAG fixed"),
        ]
    )
    .padding()
    .frame(width: 700, height: 320)
}
