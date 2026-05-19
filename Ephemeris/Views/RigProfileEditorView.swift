import SwiftUI

/// Form for creating or editing a `RigProfile`. Used in two contexts:
/// - Inline "Configure rig" prompt in the document window when a log opens without a matching profile
/// - Standalone editor reached via the (forthcoming) library window sidebar
struct RigProfileEditorView: View {
    @Binding var profile: RigProfile
    var phd2ProfileName: String?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Identity") {
                LabeledContent("PHD2 profile name") {
                    TextField("Edge-10m", text: $profile.currentName)
                        .textFieldStyle(.roundedBorder)
                }
                if !profile.nameHistory.isEmpty {
                    LabeledContent("Past names") {
                        Text(profile.nameHistory.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Mount") {
                Picker("Class", selection: $profile.mountClass) {
                    ForEach(MountClass.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                Toggle("Has high-precision encoders", isOn: $profile.hasHighPrecisionEncoders)
                    .help("PHD2's New Profile Wizard exposes this as a checkbox. When on, the recommender biases toward encoder-mount advice (LowPass2, Variable Exposure Delays).")
                LabeledContent("Mount model") {
                    TextField("10Micron GM1000HPS", text: Binding(
                        get: { profile.mountModel ?? "" },
                        set: { profile.mountModel = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }

            Section("Imaging train") {
                doubleField("Focal length", value: $profile.imagingFocalLength, unit: "mm", placeholder: "1960")
                doubleField("Pixel size", value: $profile.imagingPixelSize, unit: "μm", placeholder: "5.9")
                Picker("Binning", selection: $profile.imagingBinning) {
                    ForEach(1...4, id: \.self) { Text("\($0)×\($0)").tag($0) }
                }
                optionalDoubleField("Reducer factor",
                                    value: $profile.reducerFactor,
                                    unit: "× (e.g. 0.7)",
                                    placeholder: "leave blank for none")
                if profile.isImagingScaleConfigured {
                    LabeledContent("Computed imaging scale") {
                        Text("\(profile.imagingPixelScale, specifier: "%.3f")\" / px")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Guide train") {
                Picker("Configuration", selection: $profile.guideConfiguration) {
                    ForEach(GuideConfiguration.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                if profile.guideConfiguration != .sameOptics {
                    doubleField("Guide focal length", value: $profile.guideFocalLength, unit: "mm", placeholder: "1960")
                    doubleField("Guide pixel size", value: $profile.guideCameraPixelSize, unit: "μm", placeholder: "5.9")
                    Picker("Guide binning", selection: $profile.guideBinning) {
                        ForEach(1...4, id: \.self) { Text("\($0)×\($0)").tag($0) }
                    }
                    if profile.guidePixelScale > 0 {
                        LabeledContent("Computed guide scale") {
                            Text("\(profile.guidePixelScale, specifier: "%.3f")\" / px")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Notes") {
                TextEditor(text: Binding(
                    get: { profile.notes ?? "" },
                    set: { profile.notes = $0.isEmpty ? nil : $0 }
                ))
                .frame(minHeight: 60)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel?()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if profile.currentName.isEmpty, let phd2Name = phd2ProfileName {
                        profile.currentName = phd2Name
                    }
                    onSave?()
                    dismiss()
                }
                .disabled(profile.currentName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle(profile.currentName.isEmpty ? "New rig profile" : profile.currentName)
    }

    @ViewBuilder
    private func doubleField(_ title: String, value: Binding<Double>, unit: String, placeholder: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(placeholder, value: value, format: .number.precision(.fractionLength(0...3)))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
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
                    .frame(maxWidth: 100)
                Text(unit).foregroundStyle(.secondary).font(.caption)
            }
        }
    }
}

/// Modal-presentation wrapper used by inline prompts.
struct RigProfileEditorSheet: View {
    @State var profile: RigProfile
    var phd2ProfileName: String?
    var onSave: (RigProfile) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RigProfileEditorView(
                profile: $profile,
                phd2ProfileName: phd2ProfileName,
                onSave: { onSave(profile); dismiss() },
                onCancel: { dismiss() }
            )
        }
        .frame(minWidth: 520, minHeight: 600)
    }
}

#Preview {
    RigProfileEditorSheet(
        profile: RigProfile(currentName: "Edge-10m"),
        phd2ProfileName: "Edge-10m"
    ) { _ in }
}
