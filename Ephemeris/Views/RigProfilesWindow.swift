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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedID) {
                ForEach(store.profiles) { profile in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.currentName.isEmpty ? "(unnamed)" : profile.currentName)
                            .font(.headline)
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
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 4) {
                Button { addProfile() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Add a new rig profile")
                Button { deleteSelected() } label: { Image(systemName: "minus") }
                    .buttonStyle(.borderless)
                    .disabled(selectedID == nil)
                    .help("Delete the selected profile")
                Spacer()
                if hasUnsavedChanges {
                    Text("Unsaved changes")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.trailing, 4)
                }
            }
            .padding(8)
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
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
        } else {
            ContentUnavailableView {
                Label("No rig selected", systemImage: "scope")
            } description: {
                Text("Choose a rig profile on the left, or add a new one with the + button.")
            } actions: {
                Button("Add Rig Profile") { addProfile() }
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

    private func addProfile() {
        var new = RigProfile(currentName: "New rig")
        new.createdAt = .now
        new.modifiedAt = .now
        try? store.save(new)
        selectedID = new.id
        draft = new
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
