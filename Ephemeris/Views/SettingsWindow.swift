import SwiftUI
import SwiftData
import AppKit

/// macOS Settings pane — single, flat content area per Apple HIG. Settings is for
/// **app-wide preferences and destructive maintenance actions** only; complex
/// list-detail surfaces (rig editing, MCP server connector) live in their own
/// Window scenes.
///
/// Cmd+, opens this. Rig Profiles and MCP Server are reachable via the menu
/// (App → Rig Profiles… / MCP Server…) and live as their own resizable windows.
struct SettingsWindow: View {
    @Environment(\.ephemerisLibrary) private var library
    @State private var showingResetConfirm = false
    @State private var resetSummary: String?
    @State private var resetError: String?

    var body: some View {
        Form {
            Section("Log Library data") {
                LabeledContent("Reset Log Library data") {
                    Button("Reset…", role: .destructive) {
                        showingResetConfirm = true
                    }
                    .disabled(library == nil)
                }
                Text("Deletes every ingested night, observation, annotation, Guiding Assistant result, per-session record, and target cluster. Rig profiles are preserved. You'll need to re-import your PHD2 logs after resetting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Where things live") {
                LabeledContent("Rig profiles") {
                    Button("Open Rig Profiles…") {
                        if let url = URL(string: "ephemeris://settings/rigs") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .help("Or use the App menu → Rig Profiles… (⇧⌘,)")
                }
                LabeledContent("MCP server") {
                    Button("Open MCP Server…") {
                        if let url = URL(string: "ephemeris://settings/mcp") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .help("Or use the App menu → MCP Server…")
                }
                Text("Rig editing and the Claude MCP connector are full-window surfaces with their own list-and-detail layout, so they live outside of Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.vertical, 8)
        .navigationTitle("Settings")
        .alert(
            "Reset library data?",
            isPresented: $showingResetConfirm
        ) {
            Button("Reset", role: .destructive) {
                Task { @MainActor in
                    await performReset()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes every ingested night, observation, annotation, Guiding Assistant result, per-session record, and target cluster. Rig profiles are preserved. This cannot be undone.")
        }
        .alert(
            resetSummary ?? "",
            isPresented: Binding(
                get: { resetSummary != nil },
                set: { if !$0 { resetSummary = nil } }
            )
        ) {
            Button("OK") { resetSummary = nil }
        }
        .alert(
            resetError ?? "",
            isPresented: Binding(
                get: { resetError != nil },
                set: { if !$0 { resetError = nil } }
            )
        ) {
            Button("OK") { resetError = nil }
        }
    }

    @MainActor
    private func performReset() async {
        guard let library else {
            resetError = "Log Library is not open."
            return
        }
        do {
            // Delete on the container's main context — the same context the open
            // Library window's @Query reads from — so its night/observation lists
            // refresh after the reset instead of showing rows for deleted entities.
            let context = library.container.mainContext
            // SwiftData's batch-delete predicates need each model type listed
            // explicitly. We delete child entities before parents to keep the
            // cascade-rule timing predictable.
            try context.delete(model: ObservationEntity.self)
            try context.delete(model: AnnotationEntity.self)
            try context.delete(model: GAResultEntity.self)
            try context.delete(model: SessionRecordEntity.self)
            try context.delete(model: TargetClusterEntity.self)
            try context.delete(model: NightRecordEntity.self)
            try context.save()
            // Remove every Ephemeris donation from Spotlight so stale results stop appearing.
            CoreSpotlightIndexer.removeAll()
            // The discovery tip's counter mirrors library contents — reset it too.
            LibraryDiscoveryTipBootstrap.reset()
            resetSummary = "Log Library data reset. Re-import your PHD2 logs to rebuild the corpus."
        } catch {
            resetError = "Reset failed: \(error.localizedDescription)"
        }
    }
}
