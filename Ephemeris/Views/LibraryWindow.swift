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
    @State private var selectedRigID: RigProfile.ID?
    @State private var range: TimeRange = .month
    @State private var rigToDelete: RigProfile?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let library, let rigID = selectedRigID, let profile = rigStore.profiles.first(where: { $0.id == rigID }) {
                LibraryDetailView(profile: profile, range: range)
                    .modelContainer(library.container)
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
            if selectedRigID == nil {
                selectedRigID = rigStore.profiles.first?.id
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    chooseFolderAndImport()
                } label: {
                    Label("Import logs…", systemImage: "tray.and.arrow.down")
                }
                .disabled(library == nil)
                .help("Bulk-import every PHD2_GuideLog_*.txt from a folder. New rigs are created automatically from each log's PHD2 profile name.")
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
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        .background(
            // Hidden Button captures ⌘⌫ to delete the selected rig.
            Button("") { promptDeleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .hidden()
        )
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
        return "\(profile.effectiveName) · \(range.displayName)"
    }
}

/// Time-range selector for the library view. Per design doc §7.2.
enum TimeRange: String, CaseIterable, Sendable {
    case week, month, year, all

    var displayName: String {
        switch self {
        case .week:  return "Week"
        case .month: return "Month"
        case .year:  return "Year"
        case .all:   return "All"
        }
    }

    /// Cutoff date for the range (sessions on or after this date are included).
    /// `.all` returns the distant past.
    var cutoffDate: Date {
        let cal = Calendar.current
        switch self {
        case .week:  return cal.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        case .month: return cal.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        case .year:  return cal.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
        case .all:   return .distantPast
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
    @State private var annotatingRecord: NightRecordEntity?
    @State private var forumExportInputs: ForumPostExporter.Inputs?

    init(profile: RigProfile, range: TimeRange) {
        self.profile = profile
        self.range = range
        let rigID = profile.id
        let cutoff = range.cutoffDate
        _nightRecords = Query(
            filter: #Predicate<NightRecordEntity> { record in
                record.rigProfile?.id == rigID && record.nightDate >= cutoff
            },
            sort: \NightRecordEntity.nightDate,
            order: .reverse
        )
        _annotationEntities = Query(
            filter: #Predicate<AnnotationEntity> { ann in
                ann.rigProfileId == rigID && ann.eventDate >= cutoff
            },
            sort: \AnnotationEntity.eventDate,
            order: .reverse
        )
        _gaResults = Query(
            filter: #Predicate<GAResultEntity> { result in
                result.nightRecord?.rigProfile?.id == rigID
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

    private var recentNightsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent nights")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("·").foregroundStyle(.tertiary)
                Text("most recent first")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(nightRecords.count) total")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
                .frame(width: 110, alignment: .leading)
            Text("\(record.sessionsCount) sessions")
                .font(.callout)
                .foregroundStyle(.secondary)
            annotationBadge(for: record)
            Spacer()
            Button {
                annotatingRecord = record
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add an annotation for this night")
            Text(String(format: "%.0f min", record.totalIntegrationMinutes))
                .foregroundStyle(.secondary)
                .font(.callout.monospacedDigit())
            Text(String(format: "%.2f″", record.medianRMSArcsec))
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(verdict.tint)
                .frame(width: 60, alignment: .trailing)
            subQualityChip(for: record)
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

    /// Opens the source PHD2 log file in a new document window. Uses NSWorkspace so the
    /// existing DocumentGroup flow takes over — auto-ingest dedups, recommender runs, etc.
    /// Handles the file-moved case gracefully with a quick alert.
    private func openOriginalLog(for record: NightRecordEntity) {
        guard !record.sourceFilePath.isEmpty else { return }
        let url = URL(fileURLWithPath: record.sourceFilePath)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            let alert = NSAlert()
            alert.messageText = "Original log not found"
            alert.informativeText = "The file at \(url.path) is no longer there — it may have been moved or deleted. The analytical data Ephemeris ingested from it is still in the library."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @ViewBuilder
    private func subQualityChip(for record: NightRecordEntity) -> some View {
        let current = record.subQualityRaw.flatMap { SubQualityVerdict(rawValue: $0) }
        Menu {
            ForEach(SubQualityVerdict.allCases, id: \.self) { option in
                Button {
                    setSubQuality(option, for: record)
                } label: {
                    Label(option.displayName, systemImage: option.symbolName)
                }
            }
            if current != nil {
                Divider()
                Button("Clear rating", role: .destructive) {
                    setSubQuality(nil, for: record)
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
    }
}

