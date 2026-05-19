import SwiftUI

/// Standalone window for managing rig profiles. Two-column layout: profile list on the
/// left, editor form on the right. Opened via Shift-⌘-, (Rig Profiles… in the app menu).
///
/// The editor on the right operates on a local `draft` copy so the user can revert with
/// "Discard changes". Saving writes back into `RigProfileStore` and keeps the editor open.
struct RigProfilesWindow: View {
    @Environment(RigProfileStore.self) private var store
    @State private var selectedID: RigProfile.ID?
    @State private var draft: RigProfile?

    /// Whether the current draft differs from what's on disk.
    private var hasUnsavedChanges: Bool {
        guard let draft, let id = selectedID,
              let saved = store.profiles.first(where: { $0.id == id })
        else { return false }
        return !areEquivalent(draft, saved)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 760, minHeight: 600)
        .navigationTitle("Rig Profiles")
        .onAppear {
            if selectedID == nil {
                selectedID = store.profiles.first?.id
                draft = store.profiles.first
            }
        }
        .onChange(of: selectedID) { _, newID in
            draft = newID.flatMap { id in store.profiles.first(where: { $0.id == id }) }
        }
    }

    @State private var profileToDelete: RigProfile?

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedID) {
                ForEach(store.profiles) { profile in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.effectiveName.isEmpty ? "(unnamed)" : profile.effectiveName)
                            .font(.headline)
                        if profile.displayName?.isEmpty == false {
                            Text(profile.currentName)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        HStack(spacing: 4) {
                            Text(profile.mountClass.displayName)
                            if profile.isImagingScaleConfigured {
                                Text("·")
                                Text(String(format: "%.2f\"/px", profile.imagingPixelScale))
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .tag(profile.id)
                    .contextMenu {
                        Button(role: .destructive) {
                            profileToDelete = profile
                        } label: {
                            Label("Delete \"\(profile.effectiveName)\"", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Rigs are created automatically when you open or import PHD2 logs. The PHD2 profile name is the matching key — edit only the enrichment fields on the right.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Button(role: .destructive) {
                        if let id = selectedID,
                           let p = store.profiles.first(where: { $0.id == id }) {
                            profileToDelete = p
                        }
                    } label: {
                        Label("Delete rig", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(selectedID == nil)
                    .keyboardShortcut(.delete, modifiers: .command)
                    .help("Delete the selected rig profile (⌘⌫)")
                    Spacer()
                    if hasUnsavedChanges {
                        Text("Unsaved changes")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(8)
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        .confirmationDialog(
            "Delete this rig profile?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: profileToDelete
        ) { profile in
            Button("Delete \"\(profile.effectiveName)\"", role: .destructive) {
                try? store.delete(profile)
                if selectedID == profile.id {
                    selectedID = store.profiles.first?.id
                    draft = selectedID.flatMap { id in store.profiles.first(where: { $0.id == id }) }
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        } message: { profile in
            Text("PHD2 profile **\(profile.currentName)** — any night records and observations tied to this rig will also be removed. This can't be undone.")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedID,
           let bindingProfile = bindingForDraft() {
            RigProfileEditorView(
                profile: bindingProfile,
                phd2ProfileName: nil,
                onSave: { saveDraft(currentlySelected: id) },
                onDiscard: { reloadDraft(from: id) }
            )
            .id(id)  // Force re-render when switching between profiles
        } else if store.profiles.isEmpty {
            ContentUnavailableView {
                Label("No rigs yet", systemImage: "scope")
            } description: {
                Text("Open a PHD2 guide log or use the bulk importer in the Library window. Rigs are created automatically from each log's `Equipment Profile = …` line.")
            }
        } else {
            ContentUnavailableView {
                Label("No rig selected", systemImage: "scope")
            } description: {
                Text("Choose a rig profile on the left to edit its imaging-train values, mount class, and notes.")
            }
        }
    }

    // MARK: - Actions

    /// Wraps the @State `draft` in a non-optional Binding<RigProfile>.
    /// Returns nil when the draft itself is nil (no selection).
    private func bindingForDraft() -> Binding<RigProfile>? {
        guard draft != nil else { return nil }
        return Binding<RigProfile>(
            get: { draft ?? RigProfile() },
            set: { draft = $0 }
        )
    }

    private func deleteSelected() {
        guard let id = selectedID,
              let profile = store.profiles.first(where: { $0.id == id })
        else { return }
        try? store.delete(profile)
        selectedID = store.profiles.first?.id
        draft = selectedID.flatMap { id in store.profiles.first(where: { $0.id == id }) }
    }

    private func saveDraft(currentlySelected id: RigProfile.ID) {
        guard let d = draft else { return }
        try? store.save(d)
        // Refresh from store so the saved-state comparison shows clean
        draft = store.profiles.first(where: { $0.id == id })
    }

    private func reloadDraft(from id: RigProfile.ID) {
        draft = store.profiles.first(where: { $0.id == id })
    }

    /// Structural equivalence check for unsaved-changes detection. Ignores `modifiedAt`
    /// (bumped on every save) and timestamps so the field is meaningful.
    private func areEquivalent(_ a: RigProfile, _ b: RigProfile) -> Bool {
        a.currentName == b.currentName &&
        a.nameHistory == b.nameHistory &&
        a.imagingFocalLength == b.imagingFocalLength &&
        a.imagingPixelSize == b.imagingPixelSize &&
        a.imagingBinning == b.imagingBinning &&
        a.reducerFactor == b.reducerFactor &&
        a.guideConfiguration == b.guideConfiguration &&
        a.guideCameraPixelSize == b.guideCameraPixelSize &&
        a.guideFocalLength == b.guideFocalLength &&
        a.guideBinning == b.guideBinning &&
        a.mountModel == b.mountModel &&
        a.mountClass == b.mountClass &&
        a.hasHighPrecisionEncoders == b.hasHighPrecisionEncoders &&
        a.typicalSubExposure == b.typicalSubExposure &&
        a.notes == b.notes
    }
}
