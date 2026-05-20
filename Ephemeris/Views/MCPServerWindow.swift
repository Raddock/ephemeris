import SwiftUI
import AppKit

/// In-app surface for the embedded MCP server + one-click installers for Claude
/// Desktop and Claude Code.
///
/// Per design §5.4 + the user-feedback: setup must be one button. Two big tiles
/// invoke `ClaudeConfigInstaller` which uses the bundled helper binary + a
/// user-mediated NSOpenPanel to write each client's config file.
struct MCPServerWindow: View {
    @Environment(MCPEmbeddedServer.self) private var server
    @State private var installInProgress: ClaudeConfigInstaller.Target?
    @State private var installResult: ClaudeConfigInstaller.InstallResult?
    @State private var installError: String?
    @AppStorage("mcp.allowAnnotationWrites") private var allowWrites: Bool = false

    private var bundledBinary: URL? {
        ClaudeConfigInstaller.bundledHelperBinary()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                Divider()
                statusSection
                Divider()
                connectSection
                Divider()
                toolsSection
                Divider()
                advancedDisclosure
            }
            .padding(24)
            .frame(maxWidth: 660)
        }
        .navigationTitle("MCP Server")
        .alert(
            installError ?? "",
            isPresented: Binding(
                get: { installError != nil },
                set: { if !$0 { installError = nil } }
            )
        ) {
            Button("OK") { installError = nil }
        }
        .sheet(isPresented: Binding(
            get: { installResult != nil },
            set: { if !$0 { installResult = nil } }
        )) {
            if let result = installResult {
                InstallSuccessSheet(result: result) {
                    installResult = nil
                }
            }
        }
    }

    // MARK: - Header / status

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Connect to Claude")
                    .font(.title2.weight(.semibold))
            }
            Text("Ephemeris ships a small helper that lets Claude read your library directly. Choose your Claude client below — we'll handle the configuration in one click.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        HStack(spacing: 14) {
            statusIndicator
            Spacer()
            if let last = server.lastConnectionAt {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(server.requestCount) requests").font(.caption.monospacedDigit())
                    Text("Last \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch server.status {
        case .running(let port):
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("HTTP server running on 127.0.0.1:\(port)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .stopped:
            HStack(spacing: 6) {
                Circle().fill(.secondary).frame(width: 8, height: 8)
                Text("Server stopped").font(.callout).foregroundStyle(.secondary)
            }
        case .starting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Starting…").font(.callout).foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text("Failed: \(message)").font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Connect buttons

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                connectTile(target: .claudeDesktop,
                            icon: "macwindow",
                            iconTint: .orange,
                            subtitle: "Adds an entry to ~/Library/Application Support/Claude/claude_desktop_config.json")
                connectTile(target: .claudeCode,
                            icon: "terminal",
                            iconTint: .green,
                            subtitle: "Adds an entry to ~/.claude.json")
            }
            if bundledBinary == nil {
                Text("⚠ Helper binary not found inside the app bundle. Rebuild from Xcode to bundle it. (Dev fallback: build `tools/ephemeris-mcp/` with `swift build -c release` and the installer will find it.)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            Text("You'll see one macOS file-access prompt — that grants Ephemeris permission to update the client's config. Any existing connectors stay intact.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: $allowWrites) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Claude to add annotations")
                        .font(.callout)
                    Text("Enables the `add_annotation` write tool so Claude can record equipment changes / calibration events / notes on your behalf. Off by default. Changing this only affects subsequent installs — re-run Connect to update your existing connector.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .padding(.top, 4)
        }
    }

    private func connectTile(target: ClaudeConfigInstaller.Target,
                             icon: String,
                             iconTint: Color,
                             subtitle: String) -> some View {
        Button {
            startInstall(target)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(iconTint)
                    Text("Connect to \(target.displayName)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    if installInProgress == target {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(iconTint)
                    }
                }
                Text(subtitle)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(iconTint.opacity(0.3), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(iconTint)
                    .frame(width: 3)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10))
            }
        }
        .buttonStyle(.plain)
        .disabled(installInProgress != nil || bundledBinary == nil)
    }

    private func startInstall(_ target: ClaudeConfigInstaller.Target) {
        installInProgress = target
        Task { @MainActor in
            do {
                let result = try await ClaudeConfigInstaller.install(target, allowWrites: allowWrites)
                installResult = result
            } catch let err as ClaudeConfigInstaller.InstallError {
                if case .userCancelled = err {} else if case .noFolderSelected = err {} else {
                    installError = err.errorDescription ?? "Install failed."
                }
            } catch {
                installError = "\(error)"
            }
            installInProgress = nil
        }
    }

    // MARK: - Tools list

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Available tools")
            Text("Five read-only tools. Every observation carries a `source_authority` so Claude can distinguish PHD2-canon advice from heuristics.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                toolRow("get_corpus_summary", "High-level inventory — useful first call")
                toolRow("list_rigs", "Rig profiles with imaging-train values")
                toolRow("list_nights", "Per-night rollups (RMS, integration, target, sub-quality)")
                toolRow("list_observations", "Recommender output with severity + source authority")
                toolRow("get_aggregate_stats", "Median / p75 / p90 RMS across a rig's nights")
            }
            .font(.caption)
        }
    }

    // MARK: - Advanced

    private var advancedDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy: localhost (127.0.0.1) only. No outbound network. No telemetry.")
                Text("Helper binary: \(bundledBinary?.path ?? "(not located)")")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                if let url = server.connectionURL {
                    Text("Direct HTTP endpoint (for clients that accept localhost URLs): \(url.absoluteString)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                Text("Server controls:")
                    .font(.caption)
                    .padding(.top, 4)
                HStack {
                    Button(server.status == .stopped ? "Start server" : "Restart server") {
                        if server.status == .stopped { server.start() } else { server.restart() }
                    }
                    Button("Stop", role: .destructive) {
                        server.stop()
                    }
                    .disabled(server.status == .stopped)
                }
            }
            .font(.caption)
        } label: {
            Text("Advanced")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }

    private func toolRow(_ name: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.caption.monospaced())
                .frame(width: 170, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

/// Success sheet shown after a successful install. Tells the user to restart
/// the target Claude client and explains what tools they'll see.
private struct InstallSuccessSheet: View {
    let result: ClaudeConfigInstaller.InstallResult
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.wasFirstInstall
                         ? "Connected to \(result.target.displayName)"
                         : "Updated \(result.target.displayName) connector")
                        .font(.headline)
                    Text("Restart \(result.target.displayName) to see the Ephemeris tools appear.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                row("Config file", value: result.configFileURL.path)
                row("Helper binary", value: result.binaryPath)
            }
            .font(.caption.monospaced())
            HStack {
                Button("Reveal config in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([result.configFileURL])
                }
                Spacer()
                Button("Done") {
                    onDismiss()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
