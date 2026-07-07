//
//  SessionInspectorView.swift
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

struct SessionInspectorView: View {
    let log: GuideLog
    let section: GuideLog.SectionRef
    @Binding var selectedTime: Double?
    let manualExclusions: [ClosedRange<Double>]

    @Environment(RigProfileStore.self) private var rigStore
    @Environment(\.ephemerisLibrary) private var library
    @State private var showConfigureRigSheet = false

    /// PHD2 profile name parsed from the most recent guide-session header.
    /// Used to resolve the matching `RigProfile` (current or historical).
    private var phd2ProfileName: String? {
        for session in log.guideSessions.reversed() {
            for line in session.rawHeader {
                if let range = line.range(of: "Equipment Profile = ") {
                    let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
            }
        }
        return nil
    }

    private var matchedProfile: RigProfile? {
        guard let name = phd2ProfileName else { return nil }
        return rigStore.profile(matchingPHD2Name: name)
    }

    /// Recommender observations for the whole log. Recomputed on each inspector render —
    /// fine at Phase 2 volumes; Phase 3 will cache via `NightRecord`.
    private var observations: [RecommenderObservation] {
        guard let profile = matchedProfile else { return [] }
        return RecommenderEngine.default.analyze(log: log, profile: profile)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let profile = matchedProfile {
                    ObservationsPanel(observations: observations,
                                      title: "Observations · \(profile.effectiveName)")
                } else if let name = phd2ProfileName {
                    rigConfigurePrompt(phd2Name: name)
                }
                switch section {
                case .summary:
                    EmptyView()
                case .guide(let i):
                    if log.guideSessions[i].malformedFieldCount > 0 {
                        suspectDataBanner(count: log.guideSessions[i].malformedFieldCount)
                    }
                    guideContent(log.guideSessions[i])
                case .calibration(let i):
                    calibrationContent(log.calibrations[i])
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        // 12pt trailing gutter matches Mail.app's inspector — keeps the
        // scrollbar from sitting flush against the rounded card edges.
        .contentMargins(.trailing, 12, for: .scrollContent)
    }

    /// Pulls guide-train values from the latest session header for use as a hint when
    /// configuring a new rig profile.
    private var guideTrainHint: RigProfileEditorView.GuideTrainHint? {
        guard let session = log.guideSessions.last else { return nil }
        let props = session.headerProperties
        guard let fl = props.guideFocalLengthMm,
              let pix = props.guideCameraPixelSizeMicrons
        else { return nil }
        return RigProfileEditorView.GuideTrainHint(
            focalLengthMm: fl,
            pixelSizeMicrons: pix,
            binning: props.guideBinning ?? 1,
            cameraName: props.guideCameraName
        )
    }

    /// Shown when the parser had to coerce unreadable values to zero. Without
    /// this, a damaged log can read as suspiciously perfect guiding.
    @ViewBuilder
    private func suspectDataBanner(count: Int) -> some View {
        InspectorCard("Damaged data in this log", systemImage: "exclamationmark.triangle") {
            Text("\(count) value\(count == 1 ? "" : "s") in this session couldn't be read and \(count == 1 ? "was" : "were") treated as zero. The statistics below may understate the real guiding error.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("This usually means the log file was truncated or corrupted on disk. If you have the original, re-copy it and reopen.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func rigConfigurePrompt(phd2Name: String) -> some View {
        InspectorCard("Rig profile", systemImage: "scope") {
            Text("This log was produced by PHD2 profile **“\(phd2Name)”**, but no Ephemeris rig profile matches that name.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Configure a rig profile to enable imaging-scale verdicts and the full recommender.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button {
                showConfigureRigSheet = true
            } label: {
                Label("Configure rig for \(phd2Name)", systemImage: "scope")
            }
            .controlSize(.small)
            .padding(.top, 4)
        }
        .sheet(isPresented: $showConfigureRigSheet) {
            RigProfileConfigureSheet(
                phd2Name: phd2Name,
                guideTrainHint: guideTrainHint
            ) { newProfile in
                try? rigStore.save(newProfile)
            }
        }
    }

    @ViewBuilder
    private func guideContent(_ s: GuideSession) -> some View {
        let stats = SessionStatsCalculator.calculate(s, manualExclusionRanges: manualExclusions)
        InspectorCard("Session", systemImage: "calendar") {
            LabeledContent("Frames", value: framesValue(stats: stats, total: s.frameCount))
            LabeledContent("Duration", value: formatDuration(s.duration))
            if let date = s.startedAt {
                LabeledContent("Started", value: date.formatted(date: .abbreviated, time: .shortened))
            }
        }

        InspectorCard("Statistics", systemImage: "chart.bar.xaxis") {
            colorStatRow("RMS RA", value: distance(stats.rmsRA, scale: s.pixelScale), tint: raTint)
            colorStatRow("RMS Dec", value: distance(stats.rmsDec, scale: s.pixelScale), tint: decTint)
            LabeledContent("Total RMS") {
                Text(distance(stats.rmsTotal, scale: s.pixelScale))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            colorStatRow("Peak RA", value: distance(stats.peakRA, scale: s.pixelScale), tint: raTint)
            colorStatRow("Peak Dec", value: distance(stats.peakDec, scale: s.pixelScale), tint: decTint)
            colorStatRow("Drift RA", value: drift(stats.driftRA, scale: s.pixelScale), tint: raTint)
            colorStatRow("Drift Dec", value: drift(stats.driftDec, scale: s.pixelScale), tint: decTint)
            LabeledContent("Polar align", value: polarAlign(stats.polarAlignErrorArcmin))
        }

        InspectorCard("Optics", systemImage: "camera.aperture") {
            LabeledContent("Pixel scale", value: String(format: "%.3f \"/px", s.pixelScale))
            if s.declination != 0 {
                LabeledContent("Declination", value: String(format: "%.1f°", s.declination * 180.0 / .pi))
            }
        }

        InspectorCard("Mount", systemImage: "scope") {
            LabeledContent("Name", value: trimQuotes(s.mount.name).isEmpty ? "—" : trimQuotes(s.mount.name))
            LabeledContent("Guiding enabled", value: s.mount.guidingEnabled ? "Yes" : "No")
            if let mr = s.mount.maxRADuration {
                colorLabeledRow("Max RA duration", value: "\(mr) ms", tint: raTint)
            }
            if let md = s.mount.maxDecDuration {
                colorLabeledRow("Max Dec duration", value: "\(md) ms", tint: decTint)
            }
            if let alg = s.mount.xGuideAlgorithm {
                colorLabeledRow("RA algorithm", value: alg, tint: raTint)
            }
            if let alg = s.mount.yGuideAlgorithm {
                colorLabeledRow("Dec algorithm", value: alg, tint: decTint)
            }
            if let mm = s.mount.minMoveX {
                colorLabeledRow("RA min move", value: String(format: "%.3f px", mm), tint: raTint)
            }
            if let mm = s.mount.minMoveY {
                colorLabeledRow("Dec min move", value: String(format: "%.3f px", mm), tint: decTint)
            }
        }

        if let ao = s.ao {
            InspectorCard("AO", systemImage: "lens") {
                LabeledContent("Name", value: trimQuotes(ao.name))
                if let alg = ao.xGuideAlgorithm {
                    colorLabeledRow("X algorithm", value: alg, tint: raTint)
                }
                if let alg = ao.yGuideAlgorithm {
                    colorLabeledRow("Y algorithm", value: alg, tint: decTint)
                }
            }
        }

        if !s.infos.isEmpty {
            InspectorCard("Events", systemImage: "bell", count: s.infos.count) {
                ForEach(s.infos) { info in
                    let t = time(forInfoFrame: info.frame, in: s)
                    Button {
                        if let t { selectedTime = t }
                    } label: {
                        EventRow(info: info, time: t, isSelected: isSelected(t))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Colored row helpers

    private var raTint: Color { Color(nsColor: .systemRed) }
    private var decTint: Color { Color(nsColor: .systemBlue) }

    private func colorStatRow(_ label: String, value: String, tint: Color) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(tint)
                .monospacedDigit()
        } label: {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(label)
            }
        }
    }

    private func colorLabeledRow(_ label: String, value: String, tint: Color) -> some View {
        LabeledContent {
            Text(value).foregroundStyle(.secondary)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(label)
            }
        }
    }

    private func isSelected(_ time: Double?) -> Bool {
        guard let time, let sel = selectedTime else { return false }
        return abs(time - sel) < 0.5
    }

    private func time(forInfoFrame frame: Int, in s: GuideSession) -> Double? {
        // Sentinel-safe lookup: skip NaN entries so click-to-jump on an event
        // resolves to a real frame, never to the inter-session gap.
        let realEntries = s.entries.filter { !$0.raRawDistance.isNaN }
        guard !realEntries.isEmpty else { return nil }
        if frame <= 0 { return realEntries.first?.time }
        if let entry = realEntries.first(where: { $0.frame >= frame }) {
            return entry.time
        }
        return realEntries.last?.time
    }

    @ViewBuilder
    private func calibrationContent(_ c: Calibration) -> some View {
        let d = c.details
        InspectorCard("Calibration", systemImage: "scope") {
            LabeledContent("Device", value: c.device == .ao ? "AO" : "Mount")
            LabeledContent("Steps", value: "\(c.entries.count)")
            if let date = c.startedAt {
                LabeledContent("Started", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let ortho = d.orthogonalityErrorDeg {
                LabeledContent("Orthogonality error") {
                    Text(String(format: "%.2f°", ortho))
                        .foregroundStyle(ortho > 5 ? Color(nsColor: .systemOrange) : .secondary)
                        .monospacedDigit()
                }
            }
        }

        if d.pixelScale != nil || d.exposureMs != nil || d.calibrationStepMs != nil
            || d.calibrationDistancePx != nil || d.assumeOrthogonalAxes != nil {
            InspectorCard("Configuration", systemImage: "gearshape") {
                if let v = d.pixelScale {
                    LabeledContent("Pixel scale", value: String(format: "%.3f \"/px", v))
                }
                if let v = d.exposureMs {
                    LabeledContent("Exposure", value: "\(v) ms")
                }
                if let v = d.calibrationStepMs {
                    LabeledContent("Cal step", value: "\(v) ms")
                }
                if let v = d.calibrationDistancePx {
                    LabeledContent("Cal distance", value: "\(v) px")
                }
                if let v = d.assumeOrthogonalAxes {
                    LabeledContent("Orthogonal axes", value: v ? "Assumed" : "Measured")
                }
            }
        }
        if d.raGuideSpeedArcsecPerSec != nil || d.decGuideSpeedArcsecPerSec != nil || d.declinationRad != nil {
            InspectorCard("Mount", systemImage: "scope") {
                if let v = d.raGuideSpeedArcsecPerSec {
                    colorLabeledRow("RA guide speed", value: String(format: "%.2f \"/s", v), tint: raTint)
                }
                if let v = d.decGuideSpeedArcsecPerSec {
                    colorLabeledRow("Dec guide speed", value: String(format: "%.2f \"/s", v), tint: decTint)
                }
                if let v = d.declinationRad {
                    LabeledContent("Declination", value: String(format: "%.1f°", v * 180 / .pi))
                }
                if let v = d.hourAngleHours {
                    LabeledContent("Hour angle", value: String(format: "%+.2f h", v))
                }
                if let v = d.pierSide {
                    LabeledContent("Pier side", value: v.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        if !d.legCompletions.isEmpty {
            InspectorCard("Legs", systemImage: "arrow.triangle.branch") {
                ForEach(directionOrder, id: \.self) { dir in
                    if let leg = d.legCompletions[dir] {
                        legRow(dir, leg)
                    }
                }
            }
        }
        let counts = Dictionary(grouping: c.entries, by: \.direction).mapValues(\.count)
        if !counts.isEmpty {
            InspectorCard("Steps by direction", systemImage: "list.number") {
                ForEach(directionOrder, id: \.self) { dir in
                    if let n = counts[dir], n > 0 {
                        LabeledContent(dir.rawValue.capitalized, value: "\(n)")
                    }
                }
            }
        }
    }

    private func legRow(_ dir: CalibrationEntry.Direction, _ leg: LegCompletion) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(dir.rawValue.capitalized)
                Spacer()
                Text(String(format: "%.1f° · %.3f px/s", leg.angleDeg, leg.ratePxPerSec))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let p = leg.parity {
                HStack {
                    Spacer()
                    Text("Parity: \(p)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private let directionOrder: [CalibrationEntry.Direction] = [.west, .east, .north, .south, .backlash]

    private func framesValue(stats: SessionStats, total: Int) -> String {
        if stats.excludedFrames > 0 {
            return "\(stats.includedFrames) included · \(stats.excludedFrames) excluded"
        }
        return "\(total)"
    }

    /// Show both pixel and arcsec values so the inspector tells the full story
    /// regardless of the chart's units toggle.
    private func distance(_ valuePx: Double, scale: Double) -> String {
        let arcsec = valuePx * scale
        return String(format: "%.2f\" · %.2f px", arcsec, valuePx)
    }

    private func drift(_ pxPerMin: Double, scale: Double) -> String {
        let arcsecPerMin = pxPerMin * scale
        return String(format: "%+.2f\"/min · %+.3f px/min", arcsecPerMin, pxPerMin)
    }

    private func polarAlign(_ arcmin: Double?) -> String {
        guard let v = arcmin else { return "—" }
        return String(format: "%.2f′", v)
    }

    private func trimQuotes(_ s: String) -> String {
        var t = s
        if t.hasPrefix("\"") { t.removeFirst() }
        if t.hasSuffix("\"") { t.removeLast() }
        return t
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, sec) }
        return "\(sec)s"
    }
}

private struct EventRow: View {
    let info: InfoEntry
    let time: Double?
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.text)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    if let t = time { Text(timeText(t)) }
                    Text("·").foregroundStyle(.tertiary)
                    Text("Frame \(info.frame)")
                    if info.repeats > 1 {
                        Text("·").foregroundStyle(.tertiary)
                        Text("×\(info.repeats)")
                            .foregroundStyle(.tint)
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch info.kind {
        case .settlingStarted:      return "hourglass"
        case .settlingComplete:     return "checkmark.circle"
        case .settlingFailed:       return "exclamationmark.triangle"
        case .dither:               return "arrow.triangle.swap"
        case .mountGeometryChange:  return "gearshape"
        case .calibrationRejected:  return "xmark.circle"
        case .loopingExposures:     return "camera"
        case .starLost:             return "sparkles"
        case .frameDropped:         return "exclamationmark.octagon"
        case .parameterChange:      return "slider.horizontal.3"
        case .setLockPos:           return "scope"
        case .serverEvent:          return "server.rack"
        case .other:                return "info.circle"
        }
    }

    private var tint: Color {
        switch info.kind {
        case .settlingComplete:     return Color(nsColor: .systemGreen)
        case .settlingFailed:       return Color(nsColor: .systemOrange)
        case .dither:               return Color(nsColor: .systemPurple)
        case .mountGeometryChange:  return Color(nsColor: .systemTeal)
        case .calibrationRejected:  return Color(nsColor: .systemRed)
        case .starLost, .frameDropped: return Color(nsColor: .systemOrange)
        default:                    return .secondary
        }
    }

    private func timeText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

/// Bordered grouping for the inspector — darker fill and thin separator
/// stroke so each card visually detaches from the inspector chrome. Header
/// sits inside the card at the top, matching Final Cut / Logic / Laminar
/// inspector conventions.
private struct InspectorCard<Content: View>: View {
    let title: String
    let systemImage: String
    let count: Int?
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        systemImage: String,
        count: Int? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .font(.callout)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let count {
                    Text("(\(count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.7), lineWidth: 0.5)
        )
    }
}
