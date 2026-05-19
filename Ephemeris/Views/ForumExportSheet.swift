import SwiftUI
import AppKit

/// Sheet for the Phase 11 "Share for help" affordance — generates a Markdown bundle
/// the user can paste into a forum post, Discord channel, or chat with Claude.
/// Lets the user pick a format and edit their question before copying.
struct ForumExportSheet: View {
    let inputs: ForumPostExporter.Inputs
    @Environment(\.dismiss) private var dismiss

    @State private var format: ForumPostExporter.Format = .markdown
    @State private var userQuestion: String = ""
    @State private var copyConfirmation: String = ""

    private var renderedText: String {
        var configured = inputs
        configured = ForumPostExporter.Inputs(
            profile: inputs.profile,
            summaries: inputs.summaries,
            observations: inputs.observations,
            annotations: inputs.annotations,
            format: format,
            userQuestion: userQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? nil : userQuestion
        )
        return ForumPostExporter.render(configured)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            controls
            Divider()
            preview
            Divider()
            footer
        }
        .frame(width: 720, height: 600)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Share for help")
                .font(.title3.weight(.semibold))
            Text("A structured summary of \(inputs.profile.effectiveName) you can paste into a forum thread, Discord channel, or chat with Claude. Edit the question, pick a format, copy to clipboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What are you asking for help with?")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $userQuestion)
                    .font(.callout)
                    .frame(height: 70)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.tertiary, lineWidth: 0.5)
                    )
            }
            Picker("Format", selection: $format) {
                ForEach(ForumPostExporter.Format.allCases, id: \.self) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(renderedText.count) chars")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            ScrollView {
                Text(renderedText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            if !copyConfirmation.isEmpty {
                Text(copyConfirmation).font(.caption).foregroundStyle(.green)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                copyToClipboard()
            } label: {
                Label("Copy to clipboard", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(renderedText, forType: .string)
        copyConfirmation = "✓ Copied (\(format.displayName))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if copyConfirmation.contains(format.displayName) {
                copyConfirmation = ""
            }
        }
    }
}
