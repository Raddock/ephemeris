import SwiftUI

/// Sheet presented from the document-window inspector when an opened log's PHD2 profile
/// name has no matching `RigProfile`. Pre-fills the guide-train values from the parsed
/// log header and offers them via a "Fill from open log" button inside the editor.
///
/// The user still has to enter the imaging-train values (PHD2 doesn't know them) — those
/// fields are the load-bearing inputs for the verdict pipeline.
struct RigProfileConfigureSheet: View {
    let phd2Name: String
    let guideTrainHint: RigProfileEditorView.GuideTrainHint?
    let onSave: (RigProfile) -> Void

    @State private var draft: RigProfile
    @Environment(\.dismiss) private var dismiss

    init(phd2Name: String,
         guideTrainHint: RigProfileEditorView.GuideTrainHint?,
         onSave: @escaping (RigProfile) -> Void) {
        self.phd2Name = phd2Name
        self.guideTrainHint = guideTrainHint
        self.onSave = onSave
        var initial = RigProfile(currentName: phd2Name)
        // Pre-populate the guide train from the log header. The imaging train stays
        // empty so the user fills in their actual imaging camera + reducer.
        if let hint = guideTrainHint {
            initial.guideFocalLength = hint.focalLengthMm
            initial.guideCameraPixelSize = hint.pixelSizeMicrons
            initial.guideBinning = hint.binning
        }
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            RigProfileEditorView(
                profile: $draft,
                phd2ProfileName: phd2Name,
                guideTrainHint: guideTrainHint
            )
            .navigationTitle("Configure rig for \(phd2Name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create profile") {
                        if draft.currentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft.currentName = phd2Name
                        }
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.currentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 680)
    }
}
