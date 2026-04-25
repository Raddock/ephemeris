//
//  SessionDetailView.swift
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

struct SessionDetailView: View {
    let log: GuideLog
    let section: GuideLog.SectionRef
    let filename: String?
    @Binding var inspectorVisible: Bool
    let chartState: ChartViewState
    @Binding var selectedTime: Double?
    @Binding var manualExclusions: [ClosedRange<Double>]

    var body: some View {
        content
            .frame(minWidth: 480, minHeight: 320)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if case .guide = section {
                    chartControlsBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    exportMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        inspectorVisible.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                    .help("Show or hide inspector")
                    .keyboardShortcut("i", modifiers: [.command, .option])
                }
            }
    }

    @ViewBuilder
    private var exportMenu: some View {
        switch section {
        case .summary:
            EmptyView()
        case .guide(let i):
            Menu {
                let session = log.guideSessions[i]
                let baseName = exportBaseName(forGuideIndex: i)
                if let chartImage = chartCaptureImage(for: session) {
                    ShareLink(
                        item: PNGExportItem(image: chartImage, suggestedName: "\(baseName)_chart.png"),
                        preview: SharePreview("Guide chart", image: Image(nsImage: chartImage))
                    ) {
                        Label("Chart (PNG)", systemImage: "photo")
                    }
                    Divider()
                }
                ShareLink(
                    item: CSVExportItem(
                        content: CSVExporter.sessionStatsCSV(session, manualExclusionRanges: manualExclusions),
                        suggestedName: "\(baseName)_stats.csv"
                    ),
                    preview: SharePreview("Session stats", image: Image(systemName: "tablecells"))
                ) {
                    Label("Session stats (CSV)", systemImage: "tablecells")
                }
                ShareLink(
                    item: CSVExportItem(
                        content: CSVExporter.frameDataCSV(session),
                        suggestedName: "\(baseName)_frames.csv"
                    ),
                    preview: SharePreview("Frame data", image: Image(systemName: "list.number"))
                ) {
                    Label("Frame data (CSV)", systemImage: "list.number")
                }
                Divider()
                ShareLink(
                    item: CSVExportItem(
                        content: CSVExporter.aggregateCSV(log),
                        suggestedName: "\(filename ?? "phd2_log")_summary.csv"
                    ),
                    preview: SharePreview("Log summary", image: Image(systemName: "square.grid.2x2"))
                ) {
                    Label("Log summary (CSV)", systemImage: "square.grid.2x2")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export session data")
            .keyboardShortcut("e", modifiers: [.command])
        case .calibration:
            Menu {
                ShareLink(
                    item: CSVExportItem(
                        content: CSVExporter.aggregateCSV(log),
                        suggestedName: "\(filename ?? "phd2_log")_summary.csv"
                    ),
                    preview: SharePreview("Log summary", image: Image(systemName: "square.grid.2x2"))
                ) {
                    Label("Log summary (CSV)", systemImage: "square.grid.2x2")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func exportBaseName(forGuideIndex i: Int) -> String {
        let stem: String
        if let f = filename {
            stem = (f as NSString).deletingPathExtension
        } else {
            stem = "phd2_log"
        }
        return "\(stem)_session\(i + 1)"
    }

    /// Render a snapshot of the chart for export. Uses the live `chartState`
    /// (units, axes, overlays, y-scale) but with empty hover/selection so the
    /// captured image is uncluttered.
    @MainActor
    private func chartCaptureImage(for session: GuideSession) -> NSImage? {
        guard !session.entries.isEmpty else { return nil }
        let fullDomain: ClosedRange<Double> = {
            guard let first = session.entries.first?.time,
                  let last = session.entries.last?.time
            else { return 0...1 }
            return first...max(last, first + 1)
        }()
        let chart = GuideGraphView(
            session: session,
            chartState: chartState,
            hoverTime: .constant(nil),
            selectedTime: nil,
            visibleDomain: .constant(nil),
            fullDomain: fullDomain,
            manualExclusions: .constant(manualExclusions)
        )
        .background(Color(nsColor: .windowBackgroundColor))
        return renderImage(chart, size: CGSize(width: 1280, height: 600))
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .summary:
            EmptyView()   // routed to LogSummaryView at the ContentView level
        case .guide(let i):
            GuideSessionDetail(
                session: log.guideSessions[i],
                chartState: chartState,
                selectedTime: $selectedTime,
                manualExclusions: $manualExclusions
            )
        case .calibration(let i):
            CalibrationDetail(calibration: log.calibrations[i])
        }
    }

    @ViewBuilder
    private var chartControlsBar: some View {
        @Bindable var bindable = chartState
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                Picker("Units", selection: $bindable.units) {
                    ForEach(ChartViewState.Units.allCases) { u in Text(u.label).tag(u) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()

                Picker("Axes", selection: $bindable.axisMode) {
                    ForEach(ChartViewState.AxisMode.allCases) { a in Text(a.label).tag(a) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()

                Picker("Drag", selection: $bindable.dragMode) {
                    ForEach(ChartViewState.DragMode.allCases) { m in
                        Image(systemName: m.systemImage).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .help("Drag in chart: \(bindable.dragMode == .zoom ? "zoom" : "exclude frame range")")
                .fixedSize()

                Menu {
                    Picker("Y scale", selection: $bindable.yScale) {
                        Text("Auto").tag(ChartViewState.YScale.auto)
                        Divider()
                        Text("±0.5″").tag(ChartViewState.YScale.fixedArcsec(0.5))
                        Text("±1″").tag(ChartViewState.YScale.fixedArcsec(1))
                        Text("±2″").tag(ChartViewState.YScale.fixedArcsec(2))
                        Text("±5″").tag(ChartViewState.YScale.fixedArcsec(5))
                        Text("±10″").tag(ChartViewState.YScale.fixedArcsec(10))
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Y: \(bindable.yScale.label)", systemImage: "ruler")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer(minLength: 0)

                Menu {
                    Section("Series") {
                        Toggle("RA", isOn: $bindable.showRA)
                        Toggle("Dec", isOn: $bindable.showDec)
                        Toggle("Corrections", isOn: $bindable.showCorrections)
                    }
                    Section("Diagnostics") {
                        Toggle("Star mass", isOn: $bindable.showStarMass)
                        Toggle("SNR", isOn: $bindable.showSNR)
                    }
                    Section("Annotations") {
                        Toggle("Events", isOn: $bindable.showEvents)
                        Toggle("Limits", isOn: $bindable.showLimits)
                        Toggle("Grid", isOn: $bindable.showGrid)
                        Toggle("Scatter cluster", isOn: $bindable.showScatter)
                        Toggle("Hover readout", isOn: $bindable.showHoverCard)
                    }
                } label: {
                    Label("Overlays", systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

private struct GuideSessionDetail: View {
    let session: GuideSession
    let chartState: ChartViewState
    @Binding var selectedTime: Double?
    @Binding var manualExclusions: [ClosedRange<Double>]

    @State private var hoverTime: Double?
    @State private var visibleDomain: ClosedRange<Double>?
    @State private var showFrequencyAnalysis = false

    private var stats: SessionStats {
        SessionStatsCalculator.calculate(session, manualExclusionRanges: manualExclusions)
    }

    private var activeTime: Double? { hoverTime ?? selectedTime }

    private var fullDomain: ClosedRange<Double> {
        guard let first = session.entries.first?.time,
              let last = session.entries.last?.time
        else { return 0...1 }
        return first...max(last, first + 1)
    }

    private var effectiveDomain: ClosedRange<Double> {
        visibleDomain ?? fullDomain
    }

    var body: some View {
        VStack(spacing: 0) {
            statsStrip
            Divider()
            chartStack
        }
        .onChange(of: selectedTime) { _, new in
            // When the inspector (or any other source) sets a pinned frame
            // that falls outside the current zoom window, expand the chart
            // back to the full session domain so the rule is visible. Without
            // this the click looks like a no-op.
            guard let t = new, let current = visibleDomain else { return }
            if !current.contains(t) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    visibleDomain = nil
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFrequencyAnalysis = true
                } label: {
                    Label("Frequency analysis", systemImage: "waveform")
                }
                .help("Open RA / Dec frequency analysis")
                .disabled(session.entries.count < 32)
                .keyboardShortcut("f", modifiers: [.command])
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    manualExclusions.removeAll()
                } label: {
                    Label("Clear exclusions", systemImage: "rectangle.dashed.badge.record")
                }
                .help("Remove all manually excluded frame ranges")
                .disabled(manualExclusions.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    visibleDomain = nil
                } label: {
                    Label("Reset zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Reset chart to full session range")
                .disabled(visibleDomain == nil)
                .keyboardShortcut("0", modifiers: [.command])
            }
        }
        .sheet(isPresented: $showFrequencyAnalysis) {
            FrequencyAnalysisView(session: session)
        }
    }

    @ViewBuilder
    private var chartStack: some View {
        if session.entries.isEmpty {
            ContentUnavailableView(
                "No frames in this session",
                systemImage: "chart.xyaxis.line",
                description: Text("This guiding section was logged without any guide frames.")
            )
        } else {
            VStack(spacing: 4) {
                GuideGraphView(
                    session: session,
                    chartState: chartState,
                    hoverTime: $hoverTime,
                    selectedTime: selectedTime,
                    visibleDomain: $visibleDomain,
                    fullDomain: fullDomain,
                    manualExclusions: $manualExclusions
                )
                .overlay(alignment: .topTrailing) {
                    if chartState.showScatter {
                        ScatterInsetView(
                            session: session,
                            chartState: chartState,
                            activeTime: activeTime,
                            visibleDomain: visibleDomain,
                            manualExclusions: manualExclusions
                        )
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                    }
                }

                if chartState.showStarMass {
                    Divider()
                    DiagnosticGraphView(
                        session: session,
                        kind: .starMass,
                        hoverTime: $hoverTime,
                        activeTime: activeTime,
                        visibleDomain: effectiveDomain
                    )
                    .frame(height: 80)
                }
                if chartState.showSNR {
                    Divider()
                    DiagnosticGraphView(
                        session: session,
                        kind: .snr,
                        hoverTime: $hoverTime,
                        activeTime: activeTime,
                        visibleDomain: effectiveDomain
                    )
                    .frame(height: 80)
                }
            }
        }
    }

    private var statsStrip: some View {
        HStack(alignment: .top, spacing: 22) {
            stat("Frames", value: framesText)
            stat("Duration", value: formatDuration(session.duration))
            stat("Pixel scale", value: String(format: "%.3f \"/px", session.pixelScale))
            Divider().frame(height: 36).padding(.horizontal, 4)
            stat("RMS RA", value: distanceText(stats.rmsRA), tint: raTint, prominent: true)
            stat("RMS Dec", value: distanceText(stats.rmsDec), tint: decTint, prominent: true)
            stat("Total RMS", value: distanceText(stats.rmsTotal), prominent: true, emphasised: true)
            Divider().frame(height: 36).padding(.horizontal, 4)
            stat("Peak RA", value: distanceText(stats.peakRA), tint: raTint)
            stat("Peak Dec", value: distanceText(stats.peakDec), tint: decTint)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var raTint: Color { Color(nsColor: .systemRed) }
    private var decTint: Color { Color(nsColor: .systemBlue) }

    private var framesText: String {
        if stats.excludedFrames > 0 {
            return "\(stats.includedFrames) / \(session.frameCount)"
        }
        return "\(session.frameCount)"
    }

    private func distanceText(_ valuePx: Double) -> String {
        guard stats.includedFrames > 0 else { return "—" }
        let v = SessionStats.display(valuePx, as: chartState.units, pixelScale: session.pixelScale)
        switch chartState.units {
        case .pixels: return String(format: "%.2f px", v)
        case .arcsec: return String(format: "%.2f\"", v)
        }
    }

    private func stat(
        _ label: String,
        value: String,
        tint: Color? = nil,
        prominent: Bool = false,
        emphasised: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(emphasised ? .title2.monospacedDigit() : (prominent ? .title3.monospacedDigit() : .title3.monospacedDigit()))
                .fontWeight(emphasised ? .semibold : (prominent ? .medium : .regular))
                .foregroundStyle(tint ?? .primary)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, sec) }
        return "\(sec)s"
    }
}

private struct CalibrationDetail: View {
    let calibration: Calibration

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 28) {
                stat("Device", value: calibration.device == .ao ? "AO" : "Mount")
                stat("Steps", value: "\(calibration.entries.count)")
                if let date = calibration.startedAt {
                    stat("Started", value: date.formatted(date: .omitted, time: .shortened))
                }
                if let west = calibration.details.legCompletions[.west] {
                    stat("RA rate", value: String(format: "%.3f px/s", west.ratePxPerSec))
                }
                if let north = calibration.details.legCompletions[.north] {
                    stat("Dec rate", value: String(format: "%.3f px/s", north.ratePxPerSec))
                }
                if let ortho = calibration.details.orthogonalityErrorDeg {
                    stat("Ortho error",
                         value: String(format: "%.2f°", ortho),
                         tint: ortho > 5 ? Color(nsColor: .systemOrange) : nil)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            CalibrationGraphView(calibration: calibration)
        }
    }

    private func stat(_ label: String, value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
                .foregroundStyle(tint ?? .primary)
        }
    }
}
