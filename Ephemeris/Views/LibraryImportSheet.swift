import SwiftUI

/// Progress + summary sheet for `LibraryBulkImporter`.
/// Uses a fixed frame so it never collapses to invisibility (the .min/.ideal-only
/// approach didn't enforce minimum size in practice).
struct LibraryImportSheet: View {
    @Bindable var importer: LibraryBulkImporter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                contentForStatus
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footerBar
        }
        .frame(width: 580, height: 460)
        .background(KeyboardCloseHandler { dismiss() })
    }

    private var headerBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import PHD2 logs")
                    .font(.headline)
                Text("Reading every PHD2_GuideLog_*.txt in the chosen folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Always-visible close button so the user can never get stuck behind a
            // broken-rendering sheet body.
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
        }
        .padding(16)
    }

    @ViewBuilder
    private var contentForStatus: some View {
        switch importer.status {
        case .idle:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Preparing…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .running(let file, let processed, let total):
            runningView(currentFile: file, processed: processed, total: total)
        case .completed(let summary):
            summaryView(summary: summary, cancelled: false)
        case .cancelled(let summary):
            summaryView(summary: summary, cancelled: true)
        }
    }

    private var footerBar: some View {
        HStack {
            statusPill
            Spacer()
            switch importer.status {
            case .running:
                Button("Cancel", role: .destructive) {
                    importer.cancel()
                }
            default:
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusPill: some View {
        switch importer.status {
        case .idle:
            Text("Preparing…").font(.caption).foregroundStyle(.secondary)
        case .running(_, let p, let t):
            Text("\(p) of \(t)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        case .completed(let s):
            Text("\(s.imported) imported · \(s.skippedExisting) dedup · \(s.totalConsidered) total")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        case .cancelled(let s):
            Text("Cancelled after \(s.imported + s.skippedExisting)")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func runningView(currentFile: String, processed: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
        }
    }

    private func summaryView(summary: LibraryBulkImporter.Summary, cancelled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: cancelled ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(cancelled ? .orange : .green)
                    .font(.title)
                VStack(alignment: .leading) {
                    Text(cancelled ? "Import cancelled" : "Import finished")
                        .font(.headline)
                    Text("\(summary.imported) new · \(summary.skippedExisting) already in store · \(summary.totalConsidered) files considered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                summaryRow(label: "New nights imported", value: "\(summary.imported)", tint: .green)
                summaryRow(label: "Already in store (dedup)", value: "\(summary.skippedExisting)", tint: .secondary)
                summaryRow(label: "Rigs auto-created", value: "\(summary.autoCreatedRigs.count)", tint: .blue)
                summaryRow(label: "Empty / aborted files", value: "\(summary.skippedEmpty.count)", tint: .secondary)
                summaryRow(label: "Errors", value: "\(summary.errors.count)", tint: summary.errors.isEmpty ? .secondary : .red)
            }
            .padding(.top, 4)

            if !summary.autoCreatedRigs.isEmpty {
                disclosure(title: "Auto-created rigs",
                           items: summary.autoCreatedRigs,
                           detail: "These PHD2 profile names had no matching rig — Ephemeris created stubs. Open Rig Profiles (Shift-⌘-,) to add imaging-train values.")
            }
            if !summary.skippedEmpty.isEmpty {
                disclosure(title: "Skipped — empty / aborted",
                           items: summary.skippedEmpty,
                           detail: "PHD2 sometimes creates a log file but doesn't write session content. Safe to ignore.")
            }
            if !summary.errors.isEmpty {
                disclosure(title: "Errors",
                           items: summary.errors,
                           detail: nil,
                           tint: .red)
            }
        }
    }

    private func summaryRow(label: String, value: String, tint: Color) -> some View {
        HStack {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label).font(.callout)
            Spacer()
            Text(value).font(.callout.monospacedDigit())
                .foregroundStyle(tint == .secondary ? .secondary : tint)
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
            .padding(.leading, 4)
        }
        .font(.callout)
        .foregroundStyle(tint == .red ? .red : .primary)
    }
}

/// Captures Esc key as a dismiss command. macOS sheets don't have a built-in Esc binding
/// unless something with `.keyboardShortcut(.cancelAction)` exists in the responder chain;
/// this view ensures one is always present even if no Cancel button is visible yet.
private struct KeyboardCloseHandler: View {
    let onClose: () -> Void
    var body: some View {
        Button("", action: onClose)
            .keyboardShortcut(.cancelAction)
            .hidden()
    }
}
