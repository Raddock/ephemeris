import SwiftUI

/// Sheet for creating or editing an annotation on a NightRecord.
/// Per design doc §9.2: multi-select category chips, label, detail, date,
/// "This changed my rig" toggle.
struct AnnotationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Annotation
    let nightDate: Date
    let onSave: (Annotation) -> Void

    init(
        annotation: Annotation? = nil,
        nightDate: Date,
        rigProfileId: UUID,
        nightRecordId: UUID? = nil,
        onSave: @escaping (Annotation) -> Void
    ) {
        let initial = annotation ?? Annotation(
            rigProfileId: rigProfileId,
            nightRecordId: nightRecordId,
            eventDate: nightDate,
            label: ""
        )
        _draft = State(initialValue: initial)
        self.nightDate = nightDate
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 520, height: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Annotate this night")
                .font(.headline)
            Text("Captures what the engine cannot observe — equipment changes, calibrations, environment, software updates.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Date") {
                    DatePicker("", selection: $draft.eventDate, displayedComponents: [.date])
                        .labelsHidden()
                }

                LabeledContent("Label") {
                    TextField("e.g., OAG damaged and replaced", text: $draft.label)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Categories").font(.subheadline)
                    chipStrip
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Detail").font(.subheadline)
                    TextEditor(text: $draft.detail)
                        .frame(minHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.tertiary, lineWidth: 0.5)
                        )
                }

                Toggle("This changed my rig", isOn: $draft.isRigMutating)
                    .help("Marks subsequent sessions as a new rig regime. Per design §6.5, the recommender's rig-relative baseline resets from this point.")
            }
            .padding(20)
        }
    }

    private var chipStrip: some View {
        HStack(spacing: 6) {
            ForEach(AnnotationCategory.allCases, id: \.self) { category in
                let isSelected = draft.categories.contains(category)
                Button {
                    if isSelected {
                        draft.categories.remove(category)
                    } else {
                        draft.categories.insert(category)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: category.symbolName).font(.caption2)
                        Text(category.displayName).font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: Capsule())
                    .overlay(Capsule().stroke(isSelected ? Color.accentColor : .secondary.opacity(0.4), lineWidth: 0.5))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            Button("Save") {
                draft.modifiedAt = .now
                onSave(draft)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.label.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

#Preview {
    AnnotationSheet(
        nightDate: .now,
        rigProfileId: UUID(),
        nightRecordId: UUID()
    ) { _ in }
}
