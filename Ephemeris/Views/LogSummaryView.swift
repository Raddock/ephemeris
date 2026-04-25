//
//  LogSummaryView.swift
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

import SwiftUI

struct LogSummaryView: View {
    let log: GuideLog
    let filename: String?
    @Binding var selection: Set<GuideLog.SectionRef>

    private var stats: LogAggregateStats {
        LogAggregateStatsCalculator.calculate(log)
    }

    private var rows: [SessionRow] {
        let bestIdx = stats.bestSessionIndex
        let worstIdx = stats.worstSessionIndex
        // Compute per-session RMS once and find the min/max for the bar's domain.
        var stagedStats: [(Int, SessionStats)] = []
        for (idx, s) in log.guideSessions.enumerated() {
            stagedStats.append((idx, SessionStatsCalculator.calculate(s)))
        }
        let validRMS = stagedStats.compactMap { $0.1.includedFrames > 0 ? $0.1.rmsTotal : nil }
        let domainMax = validRMS.max() ?? 1.0
        return stagedStats.map { (idx, st) in
            let s = log.guideSessions[idx]
            let highlight: SessionRow.Highlight
            if idx == bestIdx { highlight = .best }
            else if idx == worstIdx { highlight = .worst }
            else { highlight = .none }
            return SessionRow(
                id: idx,
                index: idx,
                startedAt: s.startedAt,
                duration: s.duration,
                frames: s.frameCount,
                included: st.includedFrames,
                excluded: st.excludedFrames,
                rmsRA: st.rmsRA,
                rmsDec: st.rmsDec,
                rmsTotal: st.rmsTotal,
                pixelScale: s.pixelScale,
                highlight: highlight,
                rmsDomainMax: domainMax
            )
        }
    }

    @State private var tableSelection: Int?
    @State private var sortOrder: [KeyPathComparator<SessionRow>] = [
        .init(\.index, order: .forward)
    ]

    var body: some View {
        VStack(spacing: 0) {
            statsStrip
            Divider()
            table
        }
        .frame(minWidth: 600, minHeight: 320)
        .onChange(of: tableSelection) { _, new in
            guard let new else { return }
            selection = [.guide(new)]
        }
    }

    private var statsStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                stat("Guide sessions", value: "\(stats.guideSessionCount)")
                stat("Calibrations", value: "\(stats.calibrationCount)")
                stat("Total integration", value: formatDuration(stats.totalDurationSeconds))
                stat("Frames", value: framesText)
                if stats.pixelScale > 0 {
                    stat("Pixel scale", value: String(format: "%.3f \"/px", stats.pixelScale))
                }
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                stat("Aggregate RMS RA", value: distanceText(stats.weightedRMSRA), tint: raTint)
                stat("Aggregate RMS Dec", value: distanceText(stats.weightedRMSDec), tint: decTint)
                stat("Aggregate Total RMS", value: distanceText(stats.weightedRMSTotal), prominent: true)
                Divider().frame(height: 36).padding(.horizontal, 4)
                if let best = stats.bestSessionIndex, best < log.guideSessions.count {
                    bestWorstStat(label: "Best", index: best, color: bestColor, systemImage: "star.fill")
                }
                if let worst = stats.worstSessionIndex,
                   worst < log.guideSessions.count,
                   worst != stats.bestSessionIndex {
                    bestWorstStat(label: "Worst", index: worst, color: worstColor, systemImage: "exclamationmark.triangle.fill")
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var table: some View {
        Table(rows.sorted(using: sortOrder), selection: $tableSelection, sortOrder: $sortOrder) {
            TableColumn("") { r in
                qualityChip(for: r.highlight)
            }
            .width(76)

            TableColumn("Started") { r in
                Text(r.startedText).monospacedDigit()
            }
            .width(min: 90, ideal: 110)

            TableColumn("Duration", value: \.duration) { r in
                Text(formatDuration(r.duration)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 90)

            TableColumn("Frames", value: \.frames) { r in
                Text(r.framesText).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 110)

            TableColumn("RMS RA", value: \.rmsRA) { r in
                Text(distanceText(r.rmsRA)).monospacedDigit().foregroundStyle(raTint)
            }
            .width(min: 70, ideal: 90)

            TableColumn("RMS Dec", value: \.rmsDec) { r in
                Text(distanceText(r.rmsDec)).monospacedDigit().foregroundStyle(decTint)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Total RMS", value: \.rmsTotal) { r in
                HStack(spacing: 8) {
                    Text(distanceText(r.rmsTotal))
                        .monospacedDigit()
                        .fontWeight(r.highlight == .none ? .regular : .semibold)
                        .foregroundStyle(totalRMSColor(for: r))
                    qualityBar(for: r)
                }
            }
            .width(min: 130, ideal: 170)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Highlights

    private func qualityChip(for highlight: SessionRow.Highlight) -> some View {
        Group {
            switch highlight {
            case .best:
                chip(label: "Best", color: bestColor, systemImage: "star.fill")
            case .worst:
                chip(label: "Worst", color: worstColor, systemImage: "exclamationmark.triangle.fill")
            case .none:
                EmptyView()
            }
        }
    }

    private func chip(label: String, color: Color, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
            Text(label).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.5))
    }

    /// Horizontal bar showing this row's Total RMS relative to the worst in the
    /// log. Lets the reader spot quality outliers at a glance without reading
    /// numbers across rows.
    private func qualityBar(for r: SessionRow) -> some View {
        let denom = max(r.rmsDomainMax, .leastNonzeroMagnitude)
        let frac = min(max(r.rmsTotal / denom, 0), 1)
        let tint: Color = {
            switch r.highlight {
            case .best: return bestColor
            case .worst: return worstColor
            case .none:
                // Subtle gradient: small RMS = green, large RMS = orange.
                return Color.secondary.opacity(0.55)
            }
        }()
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                Capsule()
                    .fill(tint.opacity(r.highlight == .none ? 0.45 : 0.85))
                    .frame(width: max(2, geo.size.width * frac))
            }
        }
        .frame(height: 5)
    }

    private func totalRMSColor(for r: SessionRow) -> Color {
        switch r.highlight {
        case .best: return bestColor
        case .worst: return worstColor
        case .none: return .primary
        }
    }

    // MARK: - Header stats

    private func stat(_ label: String, value: String, tint: Color? = nil, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(prominent ? .title2.monospacedDigit() : .title3.monospacedDigit())
                .fontWeight(prominent ? .semibold : .regular)
                .foregroundStyle(tint ?? .primary)
        }
    }

    private func bestWorstStat(label: String, index: Int, color: Color, systemImage: String) -> some View {
        let session = log.guideSessions[index]
        let s = SessionStatsCalculator.calculate(session)
        let timeStr = session.startedAt.map { Self.timeFormatter.string(from: $0) } ?? "—"
        return Button {
            selection = [.guide(index)]
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                }
                Text("\(timeStr) · \(distanceText(s.rmsTotal))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color.opacity(0.30), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("Jump to \(label.lowercased()) session")
    }

    // MARK: - Colors

    private var raTint: Color { Color(nsColor: .systemRed) }
    private var decTint: Color { Color(nsColor: .systemBlue) }
    private var bestColor: Color { Color(nsColor: .systemGreen) }
    private var worstColor: Color { Color(nsColor: .systemOrange) }

    // MARK: - Formatters

    private var framesText: String {
        if stats.totalExcludedFrames > 0 {
            return "\(stats.totalIncludedFrames) included · \(stats.totalExcludedFrames) excluded"
        }
        return "\(stats.totalIncludedFrames)"
    }

    private func distanceText(_ valuePx: Double) -> String {
        guard valuePx > 0, stats.pixelScale > 0 else {
            return String(format: "%.2f px", valuePx)
        }
        return String(format: "%.2f\"", valuePx * stats.pixelScale)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, sec) }
        return "\(sec)s"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

private struct SessionRow: Identifiable {
    enum Highlight { case none, best, worst }

    let id: Int
    let index: Int
    let startedAt: Date?
    let duration: Double
    let frames: Int
    let included: Int
    let excluded: Int
    let rmsRA: Double
    let rmsDec: Double
    let rmsTotal: Double
    let pixelScale: Double
    let highlight: Highlight
    let rmsDomainMax: Double

    var startedText: String {
        guard let d = startedAt else { return "—" }
        return LogSummaryView_DateFormatter.short.string(from: d)
    }

    var framesText: String {
        if excluded > 0 { return "\(included) / \(frames)" }
        return "\(frames)"
    }
}

private enum LogSummaryView_DateFormatter {
    static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}
