import SwiftUI
import Charts

/// Multi-night trend chart per design doc §7.3.
///
/// - X-axis: per-night data points
/// - Y-axis: median RMS in arcseconds
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
            // Imaging-scale reference line
            if imagingPixelScale > 0 {
                RuleMark(y: .value("Imaging scale", imagingPixelScale))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Imaging scale \(String(format: "%.2f″", imagingPixelScale))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }

            // RMS line + verdict-colored points
            ForEach(nights) { night in
                LineMark(
                    x: .value("Night", night.nightDate),
                    y: .value("RMS", night.medianRMSArcsec)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1.5))

                PointMark(
                    x: .value("Night", night.nightDate),
                    y: .value("RMS", night.medianRMSArcsec)
                )
                .foregroundStyle(verdictColor(rms: night.medianRMSArcsec))
                .symbolSize(40)
            }

            // Annotation markers
            ForEach(annotations.prefix(50)) { marker in
                RuleMark(x: .value("Annotation", marker.date))
                    .foregroundStyle(.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
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
            Text("Median RMS (″)").font(.caption)
        }
        .frame(height: 280)
        .padding(.vertical, 8)
    }

    private func verdictColor(rms: Double) -> Color {
        guard imagingPixelScale > 0 else { return .secondary }
        let ratio = rms / imagingPixelScale
        if ratio < 0.7 { return .green }
        if ratio <= 1.0 { return .orange }
        return Color(red: 0.95, green: 0.45, blue: 0.45)
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
                medianRMSArcsec: 0.3 + Double(i) * 0.05
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
