import SwiftUI

/// Standalone Window content showing bulk-import progress + summary.
/// Reads the active importer from the environment coordinator. Replaces the
/// earlier .sheet-based version which collapsed to ~120×120 on macOS Tahoe
/// regardless of explicit .frame hints — a proper Window scene avoids that.
struct LibraryImportWindow: View {
    @Environment(\.importCoordinator) private var coordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let importer = coordinator?.active {
                ImportProgressContent(importer: importer, onDismiss: closeWindow)
            } else {
                ContentUnavailableView(
                    "No active import",
                    systemImage: "tray.and.arrow.down",
                    description: Text("Open the Library window and choose Import logs… to start.")
                )
            }
        }
        .frame(minWidth: 540, minHeight: 380)
        .onDisappear {
            // Traffic-light close skips the Done button — without this the importer
            // keeps ingesting headless with no UI able to reach it, and a second
            // "Import logs…" would run concurrently over the same store.
            if let importer = coordinator?.active {
                importer.cancel()
                coordinator?.active = nil
            }
        }
    }

    private func closeWindow() {
        coordinator?.active = nil
        dismiss()
    }
}

/// Body of the progress window, factored out so the Group above can switch on
/// whether there's an active importer to render.
private struct ImportProgressContent: View {
    @Bindable var importer: LibraryBulkImporter
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                statusContent
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Import PHD2 logs")
                .font(.headline)
            Text("Reading every PHD2_GuideLog_*.txt in the chosen folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    @ViewBuilder
    private var statusContent: some View {
        switch importer.status {
        case .idle:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Preparing…").font(.callout).foregroundStyle(.secondary)
            }
        case .running(let file, let processed, let total):
            running(currentFile: file, processed: processed, total: total)
        case .completed(let s):
            summaryView(s, cancelled: false)
        case .cancelled(let s):
            summaryView(s, cancelled: true)
        }
    }

    private var footer: some View {
        HStack {
            statusPill
            Spacer()
            switch importer.status {
            case .running:
                Button("Cancel", role: .destructive) { importer.cancel() }
            default:
                Button("Done", action: onDismiss)
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

    private func running(currentFile: String, processed: Int, total: Int) -> some View {
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

    private func summaryView(_ summary: LibraryBulkImporter.Summary, cancelled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: cancelled ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(cancelled ? .orange : .green)
                    .font(.title)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(cancelled ? "Import cancelled" : "Import finished")
                        .font(.headline)
                    Text("\(summary.imported) new · \(summary.skippedExisting) already in store · \(summary.totalConsidered) files considered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                row(label: "New nights imported", value: "\(summary.imported)", tint: .green)
                row(label: "Already in store (dedup)", value: "\(summary.skippedExisting)", tint: .secondary)
                row(label: "Rigs auto-created", value: "\(summary.autoCreatedRigs.count)", tint: .blue)
                row(label: "Empty / aborted files", value: "\(summary.skippedEmpty.count)", tint: .secondary)
                row(label: "Errors", value: "\(summary.errors.count)", tint: summary.errors.isEmpty ? .secondary : .red)
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
                disclosure(title: "Errors", items: summary.errors, detail: nil, tint: .red)
            }
        }
    }

    private func row(label: String, value: String, tint: Color) -> some View {
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
