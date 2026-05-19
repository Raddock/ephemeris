import SwiftUI

/// Form for creating or editing a `RigProfile`. Used in two presentation contexts:
/// - Embedded in the right pane of `RigProfilesWindow` (no modal dismiss; Save persists in place)
/// - As a sheet via `RigProfileEditorSheet` for inline "Configure rig" prompts
///
/// The view itself owns no save logic — it operates on a `Binding<RigProfile>` and reports
/// changes via `onSave` / `onDiscard` callbacks. Callers decide what those mean.
struct RigProfileEditorView: View {
    @Binding var profile: RigProfile
    var phd2ProfileName: String?
    /// Optional guide-train values harvested from an open log's header. When present,
    /// a "Suggest from open log" button appears in the Guide-train section.
    var guideTrainHint: GuideTrainHint?
    var onSave: (() -> Void)?
    var onDiscard: (() -> Void)?

    struct GuideTrainHint: Equatable, Sendable {
        let focalLengthMm: Double      // post-reducer effective FL reported by PHD2
        let pixelSizeMicrons: Double
        let binning: Int
        let cameraName: String?        // for the button label
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("PHD2 profile name", text: $profile.currentName, prompt: Text("Edge-10m"))
                    .textFieldStyle(.roundedBorder)
                if !profile.nameHistory.isEmpty {
                    LabeledContent("Past names") {
                        Text(profile.nameHistory.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let phd2 = phd2ProfileName, profile.currentName.isEmpty {
                    Text("Matched PHD2 profile: **\(phd2)**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Mount") {
                Picker("Class", selection: $profile.mountClass) {
                    ForEach(MountClass.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                Toggle("Has high-precision encoders", isOn: $profile.hasHighPrecisionEncoders)
                    .help("PHD2's New Profile Wizard exposes this checkbox. When on, the recommender biases toward encoder-mount advice (LowPass2, Variable Exposure Delays).")
                TextField("Mount model", text: Binding(
                    get: { profile.mountModel ?? "" },
                    set: { profile.mountModel = $0.isEmpty ? nil : $0 }
                ), prompt: Text("10Micron GM1000HPS"))
                .textFieldStyle(.roundedBorder)
            }

            Section {
                doubleField("OTA focal length", value: $profile.imagingFocalLength,
                            unit: "mm", placeholder: "2800")
                doubleField("Imaging camera pixel size",
                            value: $profile.imagingPixelSize,
                            unit: "μm", placeholder: "3.76")
                Picker("Binning", selection: $profile.imagingBinning) {
                    ForEach(1...4, id: \.self) { Text("\($0)×\($0)").tag($0) }
                }
                optionalDoubleField("Reducer factor", value: $profile.reducerFactor,
                                    unit: "× (e.g. 0.7)", placeholder: "leave blank for none")
                if profile.isImagingScaleConfigured {
                    LabeledContent("Computed imaging scale") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.3f\"/px", profile.imagingPixelScale))
                                .monospacedDigit()
                                .font(.callout)
                            if let reducer = profile.reducerFactor, reducer != 1.0 {
                                Text("(effective FL: \(Int((profile.imagingFocalLength * reducer).rounded()))mm)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Imaging train")
            } footer: {
                Text("Enter the OTA's nominal focal length and your **imaging** camera's pixel size. PHD2's log header doesn't know these — only the guide-train values appear there. Use the reducer factor separately if you image with a reducer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Configuration", selection: $profile.guideConfiguration) {
                    ForEach(GuideConfiguration.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                if profile.guideConfiguration != .sameOptics {
                    doubleField("Guide focal length", value: $profile.guideFocalLength,
                                unit: "mm", placeholder: "1960")
                    doubleField("Guide camera pixel size",
                                value: $profile.guideCameraPixelSize,
                                unit: "μm", placeholder: "5.9 (ZWO ASI174MM)")
                    Picker("Guide binning", selection: $profile.guideBinning) {
                        ForEach(1...4, id: \.self) { Text("\($0)×\($0)").tag($0) }
                    }
                    if profile.guidePixelScale > 0 {
                        LabeledContent("Computed guide scale") {
                            Text(String(format: "%.3f\"/px", profile.guidePixelScale))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let hint = guideTrainHint {
                        Button {
                            applyHint(hint)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "wand.and.stars")
                                Text("Fill from open log\(hint.cameraName.map { " (\($0))" } ?? "")")
                            }
                            .font(.caption)
                        }
                    }
                }
            } header: {
                Text("Guide train")
            } footer: {
                Text("These values are visible in the PHD2 log header — focal length is the post-reducer effective length when guiding through the same OTA as imaging (OAG), or the guide-scope's FL otherwise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notes") {
                TextEditor(text: Binding(
                    get: { profile.notes ?? "" },
                    set: { profile.notes = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 60)
            }

            if onSave != nil || onDiscard != nil {
                Section {
                    HStack {
                        if onDiscard != nil {
                            Button("Discard changes", role: .destructive) { onDiscard?() }
                        }
                        Spacer()
                        if let save = onSave {
                            Button("Save changes") { save() }
                                .buttonStyle(.borderedProminent)
                                .disabled(profile.currentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func applyHint(_ hint: GuideTrainHint) {
        profile.guideFocalLength = hint.focalLengthMm
        profile.guideCameraPixelSize = hint.pixelSizeMicrons
        profile.guideBinning = hint.binning
    }

    @ViewBuilder
    private func doubleField(_ title: String, value: Binding<Double>, unit: String, placeholder: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(placeholder, value: value, format: .number.precision(.fractionLength(0...3)))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 110)
                    .multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary).font(.caption)
            }
        }
    }

    @ViewBuilder
    private func optionalDoubleField(_ title: String, value: Binding<Double?>, unit: String, placeholder: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(placeholder, value: value, format: .number.precision(.fractionLength(0...3)))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 110)
                    .multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary).font(.caption)
            }
        }
    }
}

/// Modal-presentation wrapper used by inline prompts. Wraps the editor in a NavigationStack
/// with proper Cancel/Save toolbar items that dismiss when tapped.
struct RigProfileEditorSheet: View {
    @State var profile: RigProfile
    var phd2ProfileName: String?
    var onSave: (RigProfile) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RigProfileEditorView(profile: $profile, phd2ProfileName: phd2ProfileName)
                .navigationTitle(profile.currentName.isEmpty ? "New rig profile" : profile.currentName)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if profile.currentName.isEmpty, let name = phd2ProfileName {
                                profile.currentName = name
                            }
                            onSave(profile)
                            dismiss()
                        }
                        .disabled(profile.currentName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
        }
        .frame(minWidth: 540, minHeight: 640)
    }
}

#Preview("Embedded") {
    @Previewable @State var profile = RigProfile(currentName: "Edge-10m")
    RigProfileEditorView(profile: $profile, phd2ProfileName: "Edge-10m",
                         onSave: {}, onDiscard: {})
        .frame(width: 560, height: 720)
}
