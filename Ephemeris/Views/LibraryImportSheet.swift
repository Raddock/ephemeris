import SwiftUI

/// Progress + summary sheet for `LibraryBulkImporter`.
struct LibraryImportSheet: View {
    @Bindable var importer: LibraryBulkImporter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            switch importer.status {
            case .idle:
                idleView
            case .running(let file, let processed, let total):
                runningView(currentFile: file, processed: processed, total: total)
            case .completed(let summary):
                summaryView(summary: summary, cancelled: false)
            case .cancelled(let summary):
                summaryView(summary: summary, cancelled: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 540, idealWidth: 540, minHeight: 280, idealHeight: 360)
    }

    private var idleView: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Preparing…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Import PHD2 logs")
                .font(.title3.weight(.semibold))
            Text("Reading every PHD2_GuideLog_*.txt in the chosen folder. Debug logs and other files are skipped.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func runningView(currentFile: String, processed: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(processed), total: Double(total))
            HStack {
                Text("\(processed) / \(total)")
                    .font(.callout.monospacedDigit())
                Spacer()
                Text(currentFile)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .destructive) {
                    importer.cancel()
                }
            }
        }
    }

    private func summaryView(summary: LibraryBulkImporter.Summary, cancelled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: cancelled ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(cancelled ? .orange : .green)
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(cancelled ? "Import cancelled" : "Import finished")
                        .font(.headline)
                    Text("\(summary.imported) new · \(summary.skippedExisting) already in store · \(summary.totalConsidered) files considered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !summary.skippedNoProfile.isEmpty {
                disclosure(title: "\(summary.skippedNoProfile.count) skipped — no matching rig profile",
                           items: summary.skippedNoProfile,
                           detail: "Configure a rig profile that matches the PHD2 profile name shown in parentheses, then re-import.")
            }
            if !summary.skippedEmpty.isEmpty {
                disclosure(title: "\(summary.skippedEmpty.count) skipped — empty or unparseable",
                           items: summary.skippedEmpty,
                           detail: "PHD2 sometimes creates a log file but doesn't write session content (aborted session). Safe to ignore.")
            }
            if !summary.errors.isEmpty {
                disclosure(title: "\(summary.errors.count) errors",
                           items: summary.errors,
                           detail: nil,
                           tint: .red)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func disclosure(title: String,
                            items: [String],
                            detail: String?,
                            tint: Color = .secondary) -> some View {
        DisclosureGroup(title) {
            VStack(alignment: .leading, spacing: 2) {
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 4)
                }
                ForEach(items.prefix(50), id: \.self) { item in
                    Text(item)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if items.count > 50 {
                    Text("… and \(items.count - 50) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .font(.callout)
        .foregroundStyle(tint == .red ? .red : .primary)
    }
}
