import SwiftUI

/// Standalone window for managing rig profiles. Two-column layout: profile list on the
/// left, editor form on the right. Opened via Shift-⌘-, (Rig Profiles… in the app menu).
///
/// Phase 1 deliverable. The library window (Phase 6) will eventually offer the same
/// edit affordance from its sidebar, but this window remains the primary management UI.
struct RigProfilesWindow: View {
    @Environment(RigProfileStore.self) private var store
    @State private var selection: RigProfile.ID?
    @State private var draft: RigProfile?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 540)
        .navigationTitle("Rig Profiles")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(store.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.currentName.isEmpty ? "(unnamed)" : profile.currentName)
                                .font(.headline)
                            HStack(spacing: 4) {
                                Text(profile.mountClass.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if profile.isImagingScaleConfigured {
                                    Text("·").foregroundStyle(.tertiary)
                                    Text(String(format: "%.2f\"/px", profile.imagingPixelScale))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        if profile.hasHighPrecisionEncoders {
                            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("Has high-precision encoders")
                        }
                    }
                    .tag(profile.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Button {
                    addProfile()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                Button {
                    deleteProfile()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                Spacer()
            }
            .padding(8)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        .onChange(of: selection) { _, newValue in
            draft = newValue.flatMap { id in store.profiles.first(where: { $0.id == id }) }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let _ = selection,
           draft != nil {
            RigProfileEditorView(
                profile: Binding(
                    get: { draft ?? RigProfile() },
                    set: { draft = $0 }
                ),
                phd2ProfileName: nil,
                onSave: {
                    if let d = draft {
                        try? store.save(d)
                    }
                },
                onCancel: {
                    if let id = selection {
                        draft = store.profiles.first(where: { $0.id == id })
                    }
                }
            )
        } else {
            ContentUnavailableView(
                "Select a profile",
                systemImage: "scope",
                description: Text("Choose a rig profile from the sidebar, or add a new one with the + button.")
            )
        }
    }

    private func addProfile() {
        let new = RigProfile(currentName: "New rig")
        try? store.save(new)
        selection = new.id
    }

    private func deleteProfile() {
        guard let id = selection,
              let profile = store.profiles.first(where: { $0.id == id })
        else { return }
        try? store.delete(profile)
        selection = nil
        draft = nil
    }
}
