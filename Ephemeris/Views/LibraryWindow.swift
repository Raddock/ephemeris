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
    @State private var selectedRigID: RigProfile.ID?
    @State private var range: TimeRange = .month
    @State private var importer: LibraryBulkImporter?
    @State private var showingImportSheet = false
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
        .sheet(isPresented: $showingImportSheet) {
            if let imp = importer {
                LibraryImportSheet(importer: imp)
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
        guard let library else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a folder of PHD2 logs"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let imp = LibraryBulkImporter(library: library, rigStore: rigStore)
        self.importer = imp
        self.showingImportSheet = true
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
    @Environment(\.modelContext) private var modelContext
    @State private var annotatingRecord: NightRecordEntity?

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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.effectiveName).font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                Text(profile.mountClass.displayName)
                if profile.isImagingScaleConfigured {
                    Text(String(format: "%.2f″/px", profile.imagingPixelScale))
                        .monospacedDigit()
                }
                Text("\(nightRecords.count) nights · \(range.displayName.lowercased())")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var metricsRow: some View {
        let medians = nightRecords.map { $0.medianRMSArcsec }
        let totalMin = nightRecords.reduce(0.0) { $0 + $1.totalIntegrationMinutes }
        let medianRMS = medians.isEmpty ? 0 : medians.sorted()[medians.count / 2]
        HStack(spacing: 12) {
            metricCard(title: "Median RMS", value: String(format: "%.2f″", medianRMS))
            metricCard(title: "Integration", value: String(format: "%.1f h", totalMin / 60))
            metricCard(title: "Sessions",
                       value: "\(nightRecords.reduce(0) { $0 + $1.sessionsCount })")
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var recentNightsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent nights".uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            ForEach(nightRecords.prefix(20)) { record in
                nightRow(record)
                Divider()
            }
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
    }

    @ViewBuilder
    private func nightRow(_ record: NightRecordEntity) -> some View {
        HStack {
            Text(record.nightDate.formatted(date: .abbreviated, time: .omitted))
                .frame(width: 110, alignment: .leading)
            Text("\(record.sessionsCount) sessions").foregroundStyle(.secondary)
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
                .monospacedDigit()
            Text(String(format: "%.2f″", record.medianRMSArcsec))
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
        }
        .font(.callout)
        .padding(.vertical, 4)
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

