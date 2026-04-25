//
//  ContentView.swift
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

struct ContentView: View {
    let document: GuideLogDocument
    @State private var selection: Set<GuideLog.SectionRef> = [.summary]
    @State private var inspectorVisible = true
    @State private var chartState = ChartViewState()
    @State private var chartSelectedTime: Double?
    @State private var manualExclusions: [ClosedRange<Double>] = []

    var body: some View {
        NavigationSplitView {
            SessionListView(log: document.log, selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detail
        }
        .navigationTitle(document.filename ?? "PHD2 Log")
        .background(WindowSubtitleSetter(subtitle: subtitleText).frame(width: 0, height: 0))
        .onChange(of: selection) { old, new in
            // Summary is exclusive: it cannot coexist with section selections.
            // Decide based on what changed: if the user added summary, collapse
            // to summary-only; if they added other rows while summary was
            // selected, drop summary.
            let added = new.subtracting(old)
            if added.contains(.summary) && new.count > 1 {
                selection = [.summary]
                return
            }
            if !added.isEmpty, !added.contains(.summary), new.contains(.summary) {
                selection = new.subtracting([.summary])
                return
            }
            chartSelectedTime = nil
            manualExclusions = []
        }
    }

    /// Replaces macOS's automatic "Locked" subtitle (set because the document
    /// is read-only by design) with a summary that's actually useful to the
    /// reader.
    private var subtitleText: String {
        let log = document.log
        var parts: [String] = []
        if !log.phdVersion.isEmpty {
            let firstToken = log.phdVersion.split(separator: " ").first.map(String.init) ?? log.phdVersion
            parts.append("PHD2 \(firstToken)")
        }
        let guideCount = log.guideSessions.count
        let calCount = log.calibrations.count
        if guideCount > 0 {
            parts.append("\(guideCount) guiding")
        }
        if calCount > 0 {
            parts.append("\(calCount) calibration\(calCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var detail: some View {
        if selection.contains(.summary) || selection.isEmpty {
            if document.log.isEmpty {
                ContentUnavailableView(
                    "No PHD2 sessions",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("This file contains no recognized guiding or calibration sections.")
                )
            } else {
                LogSummaryView(
                    log: document.log,
                    filename: document.filename,
                    selection: $selection
                )
            }
        } else {
            let guideIndices = selection.compactMap { ref -> Int? in
                if case .guide(let i) = ref { return i } else { return nil }
            }.sorted()

            if guideIndices.count >= 2 {
                combinedDetail(guideIndices: guideIndices)
            } else if let only = selection.first {
                singleDetail(only)
            }
        }
    }

    @ViewBuilder
    private func singleDetail(_ ref: GuideLog.SectionRef) -> some View {
        SessionDetailView(
            log: document.log,
            section: ref,
            filename: document.filename,
            inspectorVisible: $inspectorVisible,
            chartState: chartState,
            selectedTime: $chartSelectedTime,
            manualExclusions: $manualExclusions
        )
        .inspector(isPresented: $inspectorVisible) {
            SessionInspectorView(
                log: document.log,
                section: ref,
                selectedTime: $chartSelectedTime,
                manualExclusions: manualExclusions
            )
            .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
    }

    /// Synthesize a one-session "virtual log" from the merged sessions and
    /// route it through the existing single-section detail flow.
    @ViewBuilder
    private func combinedDetail(guideIndices: [Int]) -> some View {
        let virtualLog = makeVirtualLog(guideIndices: guideIndices)
        SessionDetailView(
            log: virtualLog,
            section: .guide(0),
            filename: combinedFilename(count: guideIndices.count),
            inspectorVisible: $inspectorVisible,
            chartState: chartState,
            selectedTime: $chartSelectedTime,
            manualExclusions: $manualExclusions
        )
        .inspector(isPresented: $inspectorVisible) {
            SessionInspectorView(
                log: virtualLog,
                section: .guide(0),
                selectedTime: $chartSelectedTime,
                manualExclusions: manualExclusions
            )
            .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
    }

    private func makeVirtualLog(guideIndices: [Int]) -> GuideLog {
        let sources = guideIndices.map { document.log.guideSessions[$0] }
        let merged = GuideSessionMerger.merge(sources)
        var virtualLog = GuideLog()
        virtualLog.phdVersion = document.log.phdVersion
        virtualLog.logVersion = document.log.logVersion
        virtualLog.guideSessions = [merged]
        virtualLog.sections = [.guide(0)]
        return virtualLog
    }

    private func combinedFilename(count: Int) -> String? {
        guard let stem = document.filename else { return nil }
        return "\(stem) · \(count) sessions combined"
    }
}
