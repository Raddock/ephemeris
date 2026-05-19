import SwiftUI
import AppKit

/// In-app surface for the Phase 8 MCP server. Per design doc §5.4 the Preferences pane
/// shows a master toggle, a write-tool sub-toggle, and copy-config-snippet buttons for
/// Claude Desktop and Claude Code.
///
/// The toggle is informational at this stage — Claude Desktop launches the helper binary
/// on demand via the user's config file. Future: the "Enable" toggle could gate write
/// tools (Phase 8.5) or set up a launch-agent for always-on availability.
struct MCPServerWindow: View {
    @AppStorage("mcp.binaryPath") private var binaryPath: String = ""
    @AppStorage("mcp.allowWrites") private var allowWrites: Bool = false
    @State private var copyStatus: String = ""

    private var hasBinaryPath: Bool { !binaryPath.trimmingCharacters(in: .whitespaces).isEmpty }
    private var binaryExists: Bool {
        hasBinaryPath && FileManager.default.fileExists(atPath: binaryPath)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider()
                binarySection
                Divider()
                configSection
                Divider()
                writeToolsSection
                Divider()
                explainerSection
            }
            .padding(24)
            .frame(maxWidth: 640)
        }
        .navigationTitle("MCP Server")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("MCP Server")
                    .font(.title2.weight(.semibold))
            }
            Text("Exposes your Ephemeris library to Claude Desktop, Claude Code, or any other MCP-conformant client. The server is a small stdio binary the client launches on demand — no daemon, no network, no telemetry.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var binarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server binary".uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            if binaryExists {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Binary located")
                        .font(.callout)
                }
            } else if hasBinaryPath {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Path set but file not found")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("Build the helper, then point this field at the binary.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                TextField("/path/to/ephemeris-mcp", text: $binaryPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                Button("Choose…") { chooseBinary() }
            }

            DisclosureGroup("How to build the helper") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From the project root in Terminal:").font(.caption)
                    Text("cd tools/ephemeris-mcp && swift build -c release")
                        .font(.caption.monospaced())
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                    Text("Then the binary is at:").font(.caption)
                    Text("tools/ephemeris-mcp/.build/release/ephemeris-mcp")
                        .font(.caption.monospaced())
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .font(.caption)
        }
    }

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Client configuration".uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    copy(claudeDesktopConfigSnippet(), label: "Claude Desktop")
                } label: {
                    Label("Copy Claude Desktop config", systemImage: "doc.on.doc")
                }
                .disabled(!binaryExists)
                Button {
                    copy(claudeCodeConfigSnippet(), label: "Claude Code")
                } label: {
                    Label("Copy Claude Code config", systemImage: "doc.on.doc")
                }
                .disabled(!binaryExists)
            }
            if !copyStatus.isEmpty {
                Text(copyStatus).font(.caption).foregroundStyle(.green)
            }

            DisclosureGroup("Where to paste") {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Claude Desktop").font(.caption.weight(.semibold))
                        Text("~/Library/Application Support/Claude/claude_desktop_config.json")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("Restart Claude Desktop after editing.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Claude Code").font(.caption.weight(.semibold))
                        Text("~/.claude.json (or your project's .claude/mcp_servers.json)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Text("Reload the MCP servers panel from the command palette.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .font(.caption)
        }
    }

    private var writeToolsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Write tools".uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Toggle("Allow Claude to write annotations (add_annotation tool)", isOn: $allowWrites)
                .help("Deferred — Phase 8.5. Reserved for the forthcoming write-enabled MCP server build. v2.0 ships read-only by default.")
                .disabled(true)
            Text("v2.0 ships read-only: list rigs, list nights, list observations, get aggregate stats. The add_annotation write tool is planned for Phase 8.5 and gated behind this toggle.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var explainerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How it works".uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text("Claude launches the helper binary on demand. The helper reads your Library.store (the SwiftData database backing this app) in read-only mode and exposes five tools over stdio MCP. All traffic is local — there's no network surface.")
                .font(.caption)
            Text("Open a PHD2 log in this app at least once before connecting Claude — until something has been ingested, the library is empty and the tools return empty arrays.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose the ephemeris-mcp binary"
        if panel.runModal() == .OK, let url = panel.url {
            binaryPath = url.path
        }
    }

    private func copy(_ text: String, label: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copyStatus = "✓ \(label) config copied to clipboard"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if copyStatus.contains(label) { copyStatus = "" }
        }
    }

    private func claudeDesktopConfigSnippet() -> String {
        """
        {
          "mcpServers": {
            "ephemeris": {
              "command": "\(binaryPath)"
            }
          }
        }
        """
    }

    private func claudeCodeConfigSnippet() -> String {
        """
        {
          "mcpServers": {
            "ephemeris": {
              "command": "\(binaryPath)"
            }
          }
        }
        """
    }
}

#Preview {
    MCPServerWindow().frame(width: 640, height: 720)
}
