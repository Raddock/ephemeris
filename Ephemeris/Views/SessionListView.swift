//
//  SessionListView.swift
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

struct SessionListView: View {
    let log: GuideLog
    @Binding var selection: Set<GuideLog.SectionRef>

    var body: some View {
        List(selection: $selection) {
            summaryRow.tag(GuideLog.SectionRef.summary)
            Section("Sessions") {
                ForEach(Array(log.sections.enumerated()), id: \.offset) { _, section in
                    row(for: section).tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Sessions")
    }

    private var summaryRow: some View {
        sessionRow(
            symbol: "square.grid.2x2",
            tint: .accentColor,
            primary: "Summary",
            secondary: summarySubtitle
        )
    }

    private var summarySubtitle: String {
        let g = log.guideSessions.count
        let c = log.calibrations.count
        var parts: [String] = []
        if g > 0 { parts.append("\(g) guide") }
        if c > 0 { parts.append("\(c) calibration\(c == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func row(for section: GuideLog.SectionRef) -> some View {
        switch section {
        case .summary:
            EmptyView()
        case .guide(let i):
            let s = log.guideSessions[i]
            sessionRow(
                symbol: "scope",
                tint: .accentColor,
                primary: timeText(s.startedAt),
                secondary: "Guiding · \(formatDuration(s.duration))"
            )
        case .calibration(let i):
            let c = log.calibrations[i]
            let stepWord = c.entries.count == 1 ? "step" : "steps"
            let device = c.device == .ao ? "AO" : "Mount"
            sessionRow(
                symbol: "target",
                tint: .secondary,
                primary: timeText(c.startedAt),
                secondary: "Calibration · \(device) · \(c.entries.count) \(stepWord)"
            )
        }
    }

    private func sessionRow(symbol: String, tint: Color, primary: String, secondary: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(primary)
                    .font(.body)
                    .lineLimit(1)
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return Self.timeFormatter.string(from: date)
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
