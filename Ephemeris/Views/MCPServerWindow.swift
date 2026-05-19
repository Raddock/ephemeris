import SwiftUI
import AppKit

/// In-app surface for the embedded MCP server. Per design doc §5.4 + the embedded-MCP
/// feedback memory: the server lives inside the app and listens on localhost.
///
/// Important: Claude Desktop's "Custom Connector" UI requires **HTTPS** URLs for
/// remote services — it won't accept localhost HTTP. Local MCP setup uses the
/// older mechanism: edit `claude_desktop_config.json` directly. This window
/// surfaces both paths plus the Claude Code path (which DOES accept local HTTP).
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
                claudeCodeSection
                Divider()
                claudeDesktopSection
                Divider()
                toolsSection
            }
            .padding(24)
            .frame(maxWidth: 640)
        }
        .navigationTitle("MCP Server")
    }

    // MARK: - Header / status

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
            if let url = server.connectionURL {
                HStack(spacing: 8) {
                    Text(url.absoluteString)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 6))
                    Button {
                        copy(url.absoluteString, label: "URL")
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .help("Copy the server URL")
                }
            }
            if !copyConfirmation.isEmpty {
                Text(copyConfirmation).font(.caption).foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch server.status {
        case .running(let port):
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Running on 127.0.0.1:\(port)").font(.callout)
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

    // MARK: - Claude Code (recommended)

    private var claudeCodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .foregroundStyle(.green)
                sectionTitle("Claude Code")
                Text("recommended")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            }
            Text("Claude Code accepts the localhost URL directly. One terminal command and the connector is live:")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let url = server.connectionURL {
                codeBlock("claude mcp add ephemeris --transport http \(url.absoluteString)")
                    .overlay(alignment: .topTrailing) {
                        Button {
                            copy("claude mcp add ephemeris --transport http \(url.absoluteString)",
                                 label: "Claude Code command")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }
            }
            DisclosureGroup("Or edit your config file") {
                if let url = server.connectionURL {
                    Text("Add to `~/.claude.json` (or your project's `.claude/mcp_servers.json`):")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                    let snippet = #"""
                    {
                      "mcpServers": {
                        "ephemeris": {
                          "type": "http",
                          "url": "\#(url.absoluteString)"
                        }
                      }
                    }
                    """#
                    codeBlock(snippet)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                copy(snippet, label: "Claude Code config")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                        }
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Claude Desktop (config file)

    private var claudeDesktopSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "macwindow")
                    .foregroundStyle(.orange)
                sectionTitle("Claude Desktop")
            }
            Text("Claude Desktop's **Custom Connector** UI requires an HTTPS remote URL — it won't accept this localhost server directly.")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.orange.opacity(0.35), lineWidth: 0.5)
                )
            Text("The supported local path is via the config file. Two options:")
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup("Option A — stdio binary (no app required to be running)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Build the standalone helper once, then point Claude Desktop at it. Works even when this app is closed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    codeBlock("cd tools/ephemeris-mcp && swift build -c release")
                    Text("Then add to `~/Library/Application Support/Claude/claude_desktop_config.json`:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    let snippet = """
                    {
                      "mcpServers": {
                        "ephemeris": {
                          "command": "/absolute/path/to/PHD2-Log-Viewer/tools/ephemeris-mcp/.build/release/ephemeris-mcp"
                        }
                      }
                    }
                    """
                    codeBlock(snippet)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                copy(snippet, label: "Stdio config")
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                        }
                    Text("Restart Claude Desktop after editing.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)

            DisclosureGroup("Option B — mcp-proxy bridge (uses this running server)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("`mcp-proxy` is a small Node bridge that lets Claude Desktop talk to a local HTTP MCP server via stdio. Requires this app to be running.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    codeBlock("npm install -g @modelcontextprotocol/proxy")
                    if let url = server.connectionURL {
                        let snippet = """
                        {
                          "mcpServers": {
                            "ephemeris": {
                              "command": "mcp-proxy",
                              "args": ["\(url.absoluteString)"]
                            }
                          }
                        }
                        """
                        codeBlock(snippet)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    copy(snippet, label: "mcp-proxy config")
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                            }
                    }
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Tools list

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Available tools")
            Text("The server exposes five **read-only** tools. Every observation carries a `source_authority` field so Claude can distinguish PHD2-canon advice from community consensus and Ephemeris heuristics.")
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

    private func toolRow(_ name: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.caption.monospaced())
                .frame(width: 170, alignment: .leading)
            Text(description)
                .foregroundStyle(.secondary)
        }
    }

    private func codeBlock(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 5))
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
