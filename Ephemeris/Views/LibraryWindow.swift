import SwiftUI
import SwiftData

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
    }

    private var sidebar: some View {
        List(selection: $selectedRigID) {
            Section("Rigs") {
                ForEach(rigStore.profiles) { profile in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.currentName.isEmpty ? "(unnamed)" : profile.currentName)
                            .font(.headline)
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
    }

    private var rangeSubtitle: String {
        guard let rigID = selectedRigID,
              let profile = rigStore.profiles.first(where: { $0.id == rigID })
        else { return "" }
        return "\(profile.currentName) · \(range.displayName)"
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
                    recentNightsList
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.currentName).font(.title2.weight(.semibold))
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
                HStack {
                    Text(record.nightDate.formatted(date: .abbreviated, time: .omitted))
                        .frame(width: 110, alignment: .leading)
                    Text("\(record.sessionsCount) sessions").foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f min", record.totalIntegrationMinutes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(String(format: "%.2f″", record.medianRMSArcsec))
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
                .font(.callout)
                .padding(.vertical, 4)
                Divider()
            }
        }
    }
}
