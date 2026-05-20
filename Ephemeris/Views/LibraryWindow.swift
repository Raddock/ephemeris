import SwiftUI
import SwiftData
import AppKit

/// Multi-night library window per design doc §5.2 and §7.
/// Phase 6 scaffold — full feature build (hero cards, trend chart, recent nights list)
/// is layered on top in subsequent commits.
///
/// Opened via `Window → Library` (⇧⌘L). Per design doc §5.2 / §7.1 the window is never
/// auto-opened; a TipKit popover on the menu item fires when the third NightRecord lands.
struct LibraryWindow: View {
    @Environment(RigProfileStore.self) private var rigStore
    @Environment(\.ephemerisLibrary) private var library
    @Environment(\.importCoordinator) private var importCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var selectedRigID: RigProfile.ID?
    @State private var range: TimeRange = .month
    @State private var rigToDelete: RigProfile?
    @State private var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd: Date = .now

    /// Effective inclusive date window for the current `range` selection.
    /// `.custom` reads the user's date pickers; everything else uses preset offsets.
    private var dateWindow: DateInterval {
        switch range {
        case .custom:
            // Order-preserving so user-flipped pickers don't yield an empty window.
            let lo = min(customStart, customEnd)
            let hi = max(customStart, customEnd)
            // End of day for `hi` so a same-day picker still includes that day's nights.
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: hi) ?? hi
            return DateInterval(start: lo, end: endOfDay)
        case .all:
            return DateInterval(start: .distantPast, end: .distantFuture)
        default:
            return DateInterval(start: range.cutoffDate, end: .distantFuture)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let library, let rigID = selectedRigID, let profile = rigStore.profiles.first(where: { $0.id == rigID }) {
                LibraryDetailView(profile: profile, range: range, window: dateWindow)
                    .modelContainer(library.container)
                    .id(profile.id)
            } else {
                ContentUnavailableView(
                    "Select a rig",
                    systemImage: "scope",
                    description: Text("Pick a rig from the sidebar to see its multi-night trends. Rigs are configured under Shift-⌘-,.")
                )
            }
        }
        .navigationTitle("Library")
        .navigationSubtitle(rangeSubtitle)
        .onAppear {
            rigStore.load()
            if selectedRigID == nil {
                selectedRigID = rigStore.profiles.first?.id
            }
        }
        .onChange(of: controlActiveState) { _, state in
            // Re-read rig profiles whenever the Library becomes the active window.
            // Picks up imaging-scale (and other) edits made in the Rig Profiles
            // window so star-shape predictions recompute without an app relaunch.
            if state == .key { rigStore.load() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    chooseFolderAndImport()
                } label: {
                    Label("Import logs…", systemImage: "tray.and.arrow.down")
                }
                .disabled(library == nil)
                .help("Bulk-import every PHD2_GuideLog_*.txt from a folder. New rigs are created automatically from each log's PHD2 profile name. Re-importing the same folder refreshes per-session detail and observations without duplicating nights.")
            }
        }
        .confirmationDialog(
            "Delete this rig profile?",
            isPresented: Binding(
                get: { rigToDelete != nil },
                set: { if !$0 { rigToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: rigToDelete
        ) { profile in
            Button("Delete \"\(profile.effectiveName)\"", role: .destructive) {
                try? rigStore.delete(profile)
                if selectedRigID == profile.id {
                    selectedRigID = rigStore.profiles.first?.id
                }
                rigToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                rigToDelete = nil
            }
        } message: { profile in
            Text("PHD2 profile **\(profile.currentName)** — any night records and observations tied to this rig will also be removed. This can't be undone.")
        }
    }

    private func chooseFolderAndImport() {
        guard let library, let importCoordinator else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a folder of PHD2 logs"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let imp = LibraryBulkImporter(library: library, rigStore: rigStore)
        importCoordinator.active = imp
        openWindow(id: "library-import")
        imp.importFolder(url)
    }

    private var sidebar: some View {
        List(selection: $selectedRigID) {
            Section("Rigs") {
                ForEach(rigStore.profiles) { profile in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.effectiveName.isEmpty ? "(unnamed)" : profile.effectiveName)
                            .font(.headline)
                        if profile.displayName?.isEmpty == false {
                            Text(profile.currentName)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        if profile.isImagingScaleConfigured {
                            Text(String(format: "%.2f″/px imaging", profile.imagingPixelScale))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(profile.mountClass.displayName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .tag(profile.id)
                    .contextMenu {
                        Button(role: .destructive) {
                            rigToDelete = profile
                        } label: {
                            Label("Delete \"\(profile.effectiveName)\"", systemImage: "trash")
                        }
                    }
                }
            }
            Section("Range") {
                Picker("Time range", selection: $range) {
                    ForEach(TimeRange.allCases, id: \.self) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if range == .custom {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    DatePicker("To", selection: $customEnd, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        // Delete key removes the selected rig. onDeleteCommand is scoped to the
        // sidebar's first-responder focus, so — unlike the previous window-wide
        // ⌘⌫ keyboardShortcut — it can't fire while a date field is being edited.
        .onDeleteCommand { promptDeleteSelected() }
    }

    private func promptDeleteSelected() {
        guard let id = selectedRigID,
              let profile = rigStore.profiles.first(where: { $0.id == id })
        else { return }
        rigToDelete = profile
    }

    private var rangeSubtitle: String {
        guard let rigID = selectedRigID,
              let profile = rigStore.profiles.first(where: { $0.id == rigID })
        else { return "" }
        if range == .custom {
            let f = DateFormatter()
            f.dateStyle = .medium
            return "\(profile.effectiveName) · \(f.string(from: dateWindow.start)) – \(f.string(from: dateWindow.end))"
        }
        return "\(profile.effectiveName) · \(range.displayName)"
    }
}

/// Time-range selector for the library view. Per design doc §7.2.
/// `.custom` is paired with a user-chosen start/end held on `LibraryWindow`.
enum TimeRange: String, CaseIterable, Sendable {
    case week, month, year, all, custom

    var displayName: String {
        switch self {
        case .week:   return "Week"
        case .month:  return "Month"
        case .year:   return "Year"
        case .all:    return "All"
        case .custom: return "Custom range"
        }
    }

    /// Inclusive lower bound for preset ranges. `.custom` returns `.distantPast`
    /// here; the caller supplies the real bound.
    var cutoffDate: Date {
        let cal = Calendar.current
        switch self {
        case .week:   return cal.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        case .month:  return cal.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        case .year:   return cal.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
        case .all:    return .distantPast
        case .custom: return .distantPast
        }
    }
}

/// Main content area of the library window. Phase 6 scaffold — renders the rig profile,
/// session count, and a recent-nights list pulled from `NightRecordEntity`. Hero metric
/// cards, trend chart, hygiene strip, and observations panel land in Phase 7.
struct LibraryDetailView: View {
    let profile: RigProfile
    let range: TimeRange

    @Query private var nightRecords: [NightRecordEntity]
    @Query private var annotationEntities: [AnnotationEntity]
    @Query private var gaResults: [GAResultEntity]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @State private var annotatingRecord: NightRecordEntity?
    @State private var forumExportInputs: ForumPostExporter.Inputs?

    init(profile: RigProfile, range: TimeRange, window: DateInterval) {
        self.profile = profile
        self.range = range
        let rigID = profile.id
        let start = window.start
        let end = window.end
        _nightRecords = Query(
            filter: #Predicate<NightRecordEntity> { record in
                record.rigProfile?.id == rigID &&
                record.nightDate >= start &&
                record.nightDate <= end
            },
            sort: \NightRecordEntity.nightDate,
            order: .reverse
        )
        _annotationEntities = Query(
            filter: #Predicate<AnnotationEntity> { ann in
                ann.rigProfileId == rigID &&
                ann.eventDate >= start &&
                ann.eventDate <= end
            },
            sort: \AnnotationEntity.eventDate,
            order: .reverse
        )
        _gaResults = Query(
            filter: #Predicate<GAResultEntity> { result in
                result.rigProfileId == rigID
            },
            sort: \GAResultEntity.runAt,
            order: .reverse
        )
    }

    /// Cross-night observations from the recommender. Computed once per render off the
    /// SwiftData snapshots, which Phase 7 considers acceptable at typical corpus sizes.
    private var crossNightObservations: [RecommenderObservation] {
        let summaries: [NightSummary] = nightRecords
            .reversed()  // chronological
            .map { NightSummary(entity: $0) }
        let annotations: [Annotation] = annotationEntities.compactMap { Annotation(entity: $0) }
        let context = CrossNightContext(
            profile: profile,
            nights: summaries,
            annotations: annotations
        )
        return CrossNightEngine.default.analyze(context: context)
    }

    private var trendMarkers: [TrendChartView.AnnotationMarker] {
        annotationEntities.map { ann in
            TrendChartView.AnnotationMarker(
                id: ann.id,
                date: ann.eventDate,
                label: ann.label
            )
        }
    }

    private var chronologicalNights: [NightSummary] {
        nightRecords.reversed().map { NightSummary(entity: $0) }
    }

    private func prepareForumExport() {
        let summaries = nightRecords.reversed().map { NightSummary(entity: $0) }
        let annotations = annotationEntities.compactMap { Annotation(entity: $0) }
        let context = CrossNightContext(
            profile: profile,
            nights: summaries,
            annotations: annotations
        )
        let observations = CrossNightEngine.default.analyze(context: context)
        forumExportInputs = ForumPostExporter.Inputs(
            profile: profile,
            summaries: summaries,
            observations: observations,
            annotations: annotations,
            format: .markdown,
            userQuestion: nil
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !profile.isImagingScaleConfigured {
                    rigIncompleteBanner
                }
                if nightRecords.isEmpty {
                    ContentUnavailableView(
                        "No nights ingested",
                        systemImage: "moon.stars",
                        description: Text("Open a PHD2 guide log for this rig to start populating the library. Logs are automatically ingested when the document window opens.")
                    )
                } else {
                    metricsRow
                    PHD2HygieneStrip(
                        nightRecords: Array(nightRecords),
                        gaResults: Array(gaResults)
                    )
                    TrendChartView(
                        nights: chronologicalNights,
                        imagingPixelScale: profile.imagingPixelScale,
                        annotations: trendMarkers
                    )
                    ObservationsPanel(
                        observations: crossNightObservations,
                        title: "Cross-night observations · \(profile.effectiveName)"
                    )
                    recentNightsList
                }
            }
            .padding(20)
        }
    }

    private var rigRMSDistribution: [Double] {
        nightRecords.map { $0.medianRMSArcsec }
    }

    private func medianRMSValue() -> Double {
        let vals = rigRMSDistribution.filter { $0 > 0 }.sorted()
        return vals.isEmpty ? 0 : vals[vals.count / 2]
    }

    /// Loud-but-friendly banner shown when the rig profile is missing imaging-train
    /// values. Without those, StarShapePredictor returns `.unknown`, several
    /// observation generators no-op, and the user just sees a quiet library. This
    /// makes the gap explicit and offers a one-click path to fix it.
    @ViewBuilder
    private var rigIncompleteBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Imaging train not configured")
                    .font(.headline)
                Text("Several observations and the star-shape predictor need this rig's imaging focal length, pixel size, and binning to compute properly. Until they're set, you'll see fewer recommendations and no predicted-shape chips on the rows below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Configure rig…") {
                    openWindow(id: "rigProfiles")
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.orange.opacity(0.35), lineWidth: 1))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(profile.effectiveName)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    prepareForumExport()
                } label: {
                    Label("Share for help…", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(nightRecords.isEmpty)
                .help("Generate a Markdown summary of this rig — paste into a forum, Discord, or Claude chat to ask for help.")
                if profile.isImagingScaleConfigured {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.aperture")
                            .font(.caption)
                        Text(String(format: "%.2f″/px imaging", profile.imagingPixelScale))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                }
            }
            HStack(spacing: 12) {
                Label(profile.mountClass.displayName, systemImage: "scope")
                Text("•").foregroundStyle(.tertiary)
                Text("\(nightRecords.count) nights")
                Text("•").foregroundStyle(.tertiary)
                Text(range.displayName.lowercased())
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var metricsRow: some View {
        let totalMin = nightRecords.reduce(0.0) { $0 + $1.totalIntegrationMinutes }
        let medianRMS = medianRMSValue()
        let medianVerdict = NightVerdictCalculator.verdict(
            rmsArcsec: medianRMS,
            imagingPixelScale: profile.imagingPixelScale,
            rigDistribution: rigRMSDistribution
        )

        HStack(spacing: 12) {
            metricCard(
                title: "Median RMS",
                value: String(format: "%.2f″", medianRMS),
                icon: "scope",
                accent: medianVerdict.tint,
                accentLabel: medianVerdict.shortLabel
            )
            metricCard(
                title: "Integration",
                value: String(format: "%.1f h", totalMin / 60),
                icon: "clock",
                accent: .blue
            )
            metricCard(
                title: "Sessions",
                value: "\(nightRecords.reduce(0) { $0 + $1.sessionsCount })",
                icon: "rectangle.stack",
                accent: .purple
            )
        }
    }

    private func metricCard(title: String,
                            value: String,
                            icon: String,
                            accent: Color,
                            accentLabel: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                if let label = accentLabel {
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(accent.opacity(0.15), in: Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.35), lineWidth: 0.5))
                }
            }
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            // Subtle accent bar on the leading edge for visual interest
            Rectangle()
                .fill(accent)
                .frame(width: 3)
                .clipShape(
                    UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10)
                )
        }
    }

    /// Fixed widths shared by the recent-nights header and every row so the two
    /// HStacks line up. The header has no status dot, so it carries a matching
    /// leading spacer of `statusDot` width.
    private enum NightColumn {
        static let statusDot: CGFloat = 9
        static let date: CGFloat = 110
        static let open: CGFloat = 34
        static let note: CGFloat = 34
        static let integration: CGFloat = 82
        static let rms: CGFloat = 58
        static let shape: CGFloat = 64
    }

    /// Tiny column-header strip placed above the recent-nights rows. Names the
    /// trailing columns (open-log, annotation, integration, RMS, star shape) so
    /// the row isn't a mystery of glyphs.
    @ViewBuilder
    private var recentNightsColumnHeader: some View {
        HStack(spacing: 10) {
            // Mirrors the row's status dot so "Date" lines up with the row date.
            Color.clear.frame(width: NightColumn.statusDot, height: 1)
            Text("Date").font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                .frame(width: NightColumn.date, alignment: .leading)
            Text("Sessions").font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
            Spacer()
            columnLabel("Open", width: NightColumn.open)
            columnLabel("Note", width: NightColumn.note)
            columnLabel("Integration", width: NightColumn.integration, align: .trailing)
            columnLabel("RMS", width: NightColumn.rms, align: .trailing)
            columnLabel("Shape", width: NightColumn.shape)
                .help("Star shape — predicted from the night's data, or your own rating once you set one. Click a row's chip to rate it.")
        }
        .padding(.horizontal, 12)
    }

    private func columnLabel(_ text: String, width: CGFloat, align: Alignment = .center) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.medium))
            .tracking(0.3)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .fixedSize()
            .frame(width: width, alignment: align)
    }

    private var recentNightsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent nights")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("·").foregroundStyle(.tertiary)
                Text("most recent first · double-click to open the raw log")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(nightRecords.count) total")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            recentNightsColumnHeader
            VStack(spacing: 0) {
                ForEach(Array(nightRecords.prefix(20).enumerated()), id: \.element.id) { idx, record in
                    nightRow(record)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(idx.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03))
                    if idx < min(19, nightRecords.count - 1) {
                        Divider().opacity(0.4)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.3))
            )
        }
        .sheet(item: $annotatingRecord) { record in
            AnnotationSheet(
                nightDate: record.nightDate,
                rigProfileId: profile.id,
                nightRecordId: record.id
            ) { saved in
                persistAnnotation(saved, for: record)
            }
        }
        .sheet(isPresented: Binding(
            get: { forumExportInputs != nil },
            set: { if !$0 { forumExportInputs = nil } }
        )) {
            if let inputs = forumExportInputs {
                ForumExportSheet(inputs: inputs)
            }
        }
    }

    @ViewBuilder
    private func nightRow(_ record: NightRecordEntity) -> some View {
        let verdict = NightVerdictCalculator.verdict(
            rmsArcsec: record.medianRMSArcsec,
            imagingPixelScale: profile.imagingPixelScale,
            rigDistribution: rigRMSDistribution
        )
        HStack(spacing: 10) {
            Circle()
                .fill(verdict.tint)
                .frame(width: 9, height: 9)
                .help(verdict.shortLabel)
            Text(record.nightDate.formatted(date: .abbreviated, time: .omitted))
                .font(.callout.weight(.medium))
                .frame(width: NightColumn.date, alignment: .leading)
            if let target = record.catalogIdentifier {
                Text(target)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.12), in: Capsule())
                    .help(record.catalogCommonName ?? target)
            }
            Text("\(record.sessionsCount) sessions")
                .font(.callout)
                .foregroundStyle(.secondary)
            annotationBadge(for: record)
            Spacer()
            Button {
                openOriginalLog(for: record)
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(record.sourceFilePath.isEmpty)
            .help("Open this night's PHD2 log in the single-night viewer.")
            .frame(width: NightColumn.open)
            Button {
                annotatingRecord = record
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add an annotation for this night")
            .frame(width: NightColumn.note)
            Text(String(format: "%.0f min", record.totalIntegrationMinutes))
                .foregroundStyle(.secondary)
                .font(.callout.monospacedDigit())
                .frame(width: NightColumn.integration, alignment: .trailing)
            Text(String(format: "%.2f″", record.medianRMSArcsec))
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(verdict.tint)
                .frame(width: NightColumn.rms, alignment: .trailing)
            shapeChip(for: record)
                .frame(width: NightColumn.shape)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            openOriginalLog(for: record)
        }
        .contextMenu {
            Button {
                openOriginalLog(for: record)
            } label: {
                Label("Open log…", systemImage: "doc.text")
            }
            .disabled(record.sourceFilePath.isEmpty)
            Button {
                annotatingRecord = record
            } label: {
                Label("Add annotation…", systemImage: "text.bubble")
            }
        }
    }

    /// Opens the source PHD2 log file in a new document window. Routes through
    /// `SourceFolderBookmarks` so the sandbox security scope is restored before
    /// NSWorkspace hands the URL to Ephemeris's DocumentGroup. If the user hasn't
    /// granted access to the parent folder yet, the bookmark store will prompt once.
    /// Handles the file-moved case gracefully with a quick alert.
    private func openOriginalLog(for record: NightRecordEntity) {
        guard !record.sourceFilePath.isEmpty else { return }
        let url = URL(fileURLWithPath: record.sourceFilePath)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            _ = SourceFolderBookmarks.openLog(at: url.path)
        } else {
            let alert = NSAlert()
            alert.messageText = "Original log not found"
            alert.informativeText = "The file at \(url.path) is no longer there — it may have been moved or deleted. The analytical data Ephemeris ingested from it is still in the library."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Unified shape chip — replaces the prior split between "predicted" and
    /// "your rating" columns. By default shows the predicted shape from the data.
    /// When the user has rated the night, the rating wins (it's ground truth) and
    /// the predicted value is folded into the tooltip; disagreements paint the chip
    /// orange so the differential-flexure signature is hard to miss. Click the
    /// chip to rate or clear.
    @ViewBuilder
    private func shapeChip(for record: NightRecordEntity) -> some View {
        let prediction = StarShapePredictor.predict(
            night: record,
            imagingPixelScale: profile.imagingPixelScale
        )
        let userRated = record.subQualityRaw.flatMap { SubQualityVerdict(rawValue: $0) }
        let disagrees = userRated != nil && prediction.verdict != userRated && prediction != .unknown

        // What's shown on the chip face: user rating if present, else prediction.
        // Tooltip carries both so the comparison stays accessible. Computed in a
        // closure so the branching stays plain control flow, not @ViewBuilder content.
        let (primarySymbol, primaryTint, isPredicted): (String, Color, Bool) = {
            if let rated = userRated {
                return (rated.symbolName, rated.tint, false)
            } else if prediction != .unknown {
                return (predictionIcon(prediction),
                        chipTint(prediction: prediction, disagrees: false),
                        true)
            } else if profile.imagingPixelScale <= 0 {
                // Prediction can't run without the rig's imaging scale. Show a
                // ruler cue (no wand) so it reads as "needs setup", not "no data".
                return ("ruler", .secondary, false)
            } else {
                return ("circle.dashed", .secondary, true)
            }
        }()
        let resolvedTint: Color = disagrees ? .orange : primaryTint

        Menu {
            shapeRatingMenu(for: record, userRated: userRated)
        } label: {
            HStack(spacing: 3) {
                if isPredicted {
                    Image(systemName: "wand.and.stars").font(.caption2)
                }
                Image(systemName: primarySymbol).font(.caption.weight(.semibold))
            }
            .foregroundStyle(resolvedTint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(resolvedTint.opacity(0.22), in: Capsule())
            .overlay(Capsule().stroke(resolvedTint.opacity(0.55), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // .borderlessButton tints its label content from `.tint`, not
        // `.foregroundStyle` — without this the icons render a flat default
        // gray regardless of the prediction. The high-opacity capsule above
        // carries the colour signal even if a future macOS ignores `.tint`.
        .tint(resolvedTint)
        .fixedSize()
        .help(combinedShapeTooltip(prediction: prediction, userRated: userRated, disagrees: disagrees, record: record))
    }

    @ViewBuilder
    private func shapeRatingMenu(for record: NightRecordEntity, userRated: SubQualityVerdict?) -> some View {
        Button {
            setSubQuality(nil, for: record)
        } label: {
            Label("Use predicted", systemImage: "wand.and.stars")
        }
        Divider()
        ForEach(SubQualityVerdict.allCases, id: \.self) { option in
            Button {
                setSubQuality(option, for: record)
            } label: {
                Label(option.displayName, systemImage: option.symbolName)
            }
        }
    }

    private func combinedShapeTooltip(prediction: PredictedStarShape,
                                      userRated: SubQualityVerdict?,
                                      disagrees: Bool,
                                      record: NightRecordEntity) -> String {
        let scaleNote: String
        if profile.imagingPixelScale > 0 {
            let ratio = record.medianRMSArcsec / profile.imagingPixelScale
            scaleNote = String(format: " (RMS %.2f″ vs imaging scale %.2f″/px = %.2f×)",
                               record.medianRMSArcsec, profile.imagingPixelScale, ratio)
        } else {
            scaleNote = ""
        }
        var lines: [String] = []
        if let rated = userRated {
            lines.append("Your rating: \(rated.displayName)")
            if prediction != .unknown {
                lines.append("Predicted from data: \(prediction.displayName.lowercased())\(scaleNote)")
            }
        } else if prediction == .unknown && profile.imagingPixelScale <= 0 {
            lines.append("Star-shape prediction needs this rig's imaging pixel scale.")
            lines.append("Set the imaging focal length, pixel size, and binning under App → Rig Profiles… (⇧⌘,) — predicted shapes then appear here automatically.")
        } else {
            lines.append("Predicted from data: \(prediction.displayName.lowercased())\(scaleNote)")
            lines.append("(Click to rate this night against your actual subs.)")
        }
        if prediction.isBloated {
            lines.append("Bloated = symmetric guiding wider than the imaging scale. Stars stay round but appear soft. Long-FL OTAs on harmonic-strain-wave mounts often live here.")
        }
        if case .trailed(let cause) = prediction {
            lines.append(trailedCauseExplanation(cause))
        }
        if disagrees {
            lines.append("Disagreement between your rating and the data often indicates differential flexure or another between-guider-and-imager effect.")
        }
        return lines.joined(separator: "\n\n")
    }

    /// Old name kept as a no-op so we don't have to ripple-rename. Returns nothing.
    @ViewBuilder
    private func predictedShapeChip(for record: NightRecordEntity) -> some View {
        let prediction = StarShapePredictor.predict(
            night: record,
            imagingPixelScale: profile.imagingPixelScale
        )
        let userRated = record.subQualityRaw.flatMap { SubQualityVerdict(rawValue: $0) }
        let disagrees = userRated != nil && prediction.verdict != userRated && prediction != .unknown
        // Bloated round + user-rated round isn't a disagreement (they'd both pick
        // "round" from the menu) — but it IS information worth surfacing, so the
        // chip stays visible to show the bloat. We just don't paint it orange.

        if prediction != .unknown {
            // Always show — the user wants to see the data signal on every row.
            // Tint scales with severity: secondary for sharp round, the chip's
            // own color for bloated / elongated / trailed, orange for disagreements.
            let tint = chipTint(prediction: prediction, disagrees: disagrees)
            HStack(spacing: 3) {
                Image(systemName: "wand.and.stars")
                    .font(.caption2)
                Image(systemName: predictionIcon(prediction))
                    .font(.caption2)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 0.5))
            .help(predictionTooltip(prediction: prediction, userRated: userRated, disagrees: disagrees, record: record))
        }
    }

    private func chipTint(prediction: PredictedStarShape, disagrees: Bool) -> Color {
        if disagrees { return .orange }
        switch prediction {
        case .round(let bloated):   return bloated ? .yellow : .secondary
        case .slightlyElongated:    return .orange
        case .trailed:              return .red
        case .mixed:                return .yellow
        case .unknown:              return .secondary
        }
    }

    private func predictionIcon(_ prediction: PredictedStarShape) -> String {
        switch prediction {
        case .round(let bloated): return bloated ? "circle.dotted" : "circle.fill"
        case .slightlyElongated:  return "oval.fill"
        case .trailed:            return "line.diagonal"
        case .mixed:              return "circle.lefthalf.filled"
        case .unknown:            return "circle.dashed"
        }
    }

    private func trailedCauseExplanation(_ cause: PredictedStarShape.TrailedCause) -> String {
        switch cause {
        case .decDrift:
            return "Dec axis dominated the drift — that's the canonical polar-alignment-error fingerprint. The Guiding Assistant reports polar error directly; running Drift Alignment or Static Polar Alignment is the targeted fix."
        case .raDrift:
            return "RA axis dominated the drift — typical causes are mount periodic error overwhelming corrections, wind, or a tracking rate that's drifting (refraction model, sidereal vs custom)."
        case .bothAxes:
            return "Both axes drifted — that's rarer and usually means the mount lost tracking or the pointing model is unstable."
        }
    }

    private func predictionTooltip(prediction: PredictedStarShape,
                                   userRated: SubQualityVerdict?,
                                   disagrees: Bool,
                                   record: NightRecordEntity) -> String {
        let scaleNote: String
        if profile.imagingPixelScale > 0 {
            let ratio = record.medianRMSArcsec / profile.imagingPixelScale
            scaleNote = String(format: " (RMS %.2f″ vs imaging scale %.2f″/px = %.2f×)",
                               record.medianRMSArcsec, profile.imagingPixelScale, ratio)
        } else {
            scaleNote = ""
        }
        var base = "Predicted from data: \(prediction.displayName.lowercased())\(scaleNote)."
        if prediction.isBloated {
            base += " Bloated = symmetric guiding wider than the imaging scale — stars stay round but appear soft. Long-FL OTAs on harmonic-strain-wave mounts often live here."
        }
        if case .trailed(let cause) = prediction {
            base += " " + trailedCauseExplanation(cause)
        }
        if disagrees, let userRated {
            base += " You rated this night \(userRated.displayName.lowercased()). Disagreement often indicates differential flexure or another between-guider-and-imager effect."
        } else if userRated == nil {
            base += " Rate this night to compare your eye against the data."
        }
        return base
    }

    @ViewBuilder
    private func subQualityChip(for record: NightRecordEntity) -> some View {
        let current = record.subQualityRaw.flatMap { SubQualityVerdict(rawValue: $0) }
        Menu {
            Button {
                setSubQuality(nil, for: record)
            } label: {
                Label("Unrated", systemImage: "circle.dashed")
            }
            Divider()
            ForEach(SubQualityVerdict.allCases, id: \.self) { option in
                Button {
                    setSubQuality(option, for: record)
                } label: {
                    Label(option.displayName, systemImage: option.symbolName)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: current?.symbolName ?? "circle.dashed")
                    .font(.caption2)
                if let c = current {
                    Text(c.displayName)
                        .font(.caption2)
                }
            }
            .foregroundStyle(current?.tint ?? .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                (current?.tint ?? .secondary).opacity(0.12),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke((current?.tint ?? .secondary).opacity(0.35), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(current == nil
              ? "Rate this night's imaging frames"
              : "Imaging frames: \(current!.displayName)")
    }

    private func setSubQuality(_ verdict: SubQualityVerdict?, for record: NightRecordEntity) {
        record.subQualityRaw = verdict?.rawValue
        record.lastAnalyzedAt = .now
        try? modelContext.save()
    }

    @ViewBuilder
    private func annotationBadge(for record: NightRecordEntity) -> some View {
        if let annotations = record.annotations, !annotations.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "text.bubble").font(.caption2)
                Text("\(annotations.count)").font(.caption2.monospacedDigit())
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.blue.opacity(0.12), in: Capsule())
        }
    }

    private func persistAnnotation(_ annotation: Annotation, for record: NightRecordEntity) {
        let entity = AnnotationEntity()
        entity.id = annotation.id
        entity.rigProfileId = annotation.rigProfileId
        entity.nightRecord = record
        entity.eventDate = annotation.eventDate
        entity.categoriesData = (try? JSONEncoder().encode(annotation.categories.map { $0.rawValue })) ?? Data()
        entity.label = annotation.label
        entity.detail = annotation.detail
        entity.isRigMutating = annotation.isRigMutating
        entity.createdAt = annotation.createdAt
        entity.modifiedAt = annotation.modifiedAt
        modelContext.insert(entity)
        try? modelContext.save()

        // CoreSpotlight donation so this annotation is searchable from Spotlight.
        let categoryText = annotation.categories.map { $0.rawValue.capitalized }.joined(separator: " · ")
        var keywords: [String] = ["Ephemeris", "Annotation", profile.effectiveName]
        keywords.append(contentsOf: annotation.categories.map { $0.rawValue })
        CoreSpotlightIndexer.donate(annotation: AnnotationEntityDigest(
            id: annotation.id,
            title: categoryText.isEmpty ? annotation.label : "\(categoryText) · \(annotation.label)",
            subtitle: annotation.detail,
            keywords: keywords,
            eventDate: annotation.eventDate,
            modifiedAt: annotation.modifiedAt
        ))
    }
}

