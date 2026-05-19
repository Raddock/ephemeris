import SwiftUI
import AppKit

/// In-app surface for the embedded MCP server. Per design doc §5.4 + the
/// `feedback_mcp_embedded` preference, the server lives inside the app and listens
/// on localhost. The user only needs to copy one URL into Claude's connector UI.
struct MCPServerWindow: View {
    @Environment(MCPEmbeddedServer.self) private var server
    @State private var copyConfirmation: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider()
                statusSection
                Divider()
                connectionSection
                Divider()
                pasteInstructionsSection
                Divider()
                toolsSection
            }
            .padding(24)
            .frame(maxWidth: 620)
        }
        .navigationTitle("MCP Server")
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("MCP Server")
                    .font(.title2.weight(.semibold))
            }
            Text("Lets Claude (or any MCP-conformant client) read your Ephemeris library. The server runs inside this app and listens on localhost — no separate process to install, no external network surface.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Status")
            HStack(spacing: 8) {
                statusIndicator
                Spacer()
                Button(server.status == .stopped ? "Start" : "Restart") {
                    if server.status == .stopped { server.start() }
                    else { server.restart() }
                }
                Button("Stop", role: .destructive) {
                    server.stop()
                }
                .disabled(server.status == .stopped)
            }
            HStack(spacing: 12) {
                Text("Requests served: **\(server.requestCount)**")
                if let last = server.lastConnectionAt {
                    Text("Last: \(last.formatted(date: .omitted, time: .standard))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch server.status {
        case .running(let port):
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Running on port \(port)").font(.callout)
            }
        case .stopped:
            HStack(spacing: 6) {
                Circle().fill(.secondary).frame(width: 8, height: 8)
                Text("Stopped").font(.callout).foregroundStyle(.secondary)
            }
        case .starting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Starting…").font(.callout).foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Failed to start").font(.callout).foregroundStyle(.red)
                }
                Text(message).font(.caption2).foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        sectionTitle("Connection URL")
        if let url = server.connectionURL {
            HStack(spacing: 8) {
                Text(url.absoluteString)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 6))
                Button {
                    copy(url.absoluteString, label: "URL")
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            if !copyConfirmation.isEmpty {
                Text(copyConfirmation).font(.caption).foregroundStyle(.green)
            }
        } else {
            Text("Server is not running. Start it to get a connection URL.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pasteInstructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("How to connect")
            VStack(alignment: .leading, spacing: 6) {
                instructionStep(
                    number: 1,
                    title: "Open Claude Desktop or Claude Code",
                    detail: "Or any other MCP-conformant client."
                )
                instructionStep(
                    number: 2,
                    title: "Add a custom connector",
                    detail: "In Claude Desktop: Settings → Connectors → Add Custom Connector. In Claude Code: edit your .claude.json mcpServers entry to use the url field."
                )
                instructionStep(
                    number: 3,
                    title: "Paste the URL above",
                    detail: "The client will list five Ephemeris tools (list_rigs, list_nights, list_observations, get_aggregate_stats, get_corpus_summary)."
                )
            }
            DisclosureGroup("Alternative: edit Claude Desktop config file directly") {
                if let url = server.connectionURL {
                    let snippet = #"""
                    {
                      "mcpServers": {
                        "ephemeris": {
                          "url": "\#(url.absoluteString)"
                        }
                      }
                    }
                    """#
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add to ~/Library/Application Support/Claude/claude_desktop_config.json:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(snippet)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 4))
                        Button {
                            copy(snippet, label: "Config snippet")
                        } label: {
                            Label("Copy config snippet", systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)
                    }
                } else {
                    Text("Start the server to see the config snippet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Available tools")
            Text("The server exposes five **read-only** tools. Every observation carries a `source_authority` field so Claude can distinguish PHD2-canon advice from community consensus and Ephemeris heuristics.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                toolRow("get_corpus_summary", "High-level inventory — useful first call")
                toolRow("list_rigs", "Rig profiles with imaging-train values")
                toolRow("list_nights", "Per-night rollups (median RMS, integration time)")
                toolRow("list_observations", "Recommender output with severity + source authority")
                toolRow("get_aggregate_stats", "Median / p75 / p90 RMS across a rig's nights")
            }
            .font(.caption)
            Text("Privacy: the server listens on 127.0.0.1 only. No outbound network. No telemetry. Write tools (annotation creation) are planned for Phase 8.5 behind an opt-in toggle.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }

    private func instructionStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func toolRow(_ name: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.caption.monospaced())
                .frame(width: 150, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }

    private func copy(_ text: String, label: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copyConfirmation = "✓ \(label) copied to clipboard"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if copyConfirmation.contains(label) { copyConfirmation = "" }
        }
    }
}
