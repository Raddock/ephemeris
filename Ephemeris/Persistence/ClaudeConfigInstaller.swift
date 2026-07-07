import AppKit
import Foundation

/// One-click installer that wires the bundled `ephemeris-mcp` stdio helper into
/// Claude Desktop or Claude Code's config file. Per design §5.4 + the user-feedback
/// that one-button setup is non-negotiable for shipping.
///
/// **Flow per install target**:
/// 1. Find the bundled helper binary inside `Ephemeris.app/Contents/Helpers/`
/// 2. Show an `NSOpenPanel` pre-positioned at the config directory — user clicks
///    "Grant access" to authorize sandboxed writes to that folder
/// 3. Read existing JSON config (or start fresh), merge in the `ephemeris` entry,
///    write back atomically — existing entries are preserved
/// 4. Return a result struct describing what happened
///
/// The user sees: one button → NSOpenPanel confirmation → success. No terminal,
/// no JSON editing, no admin password. Two clicks total.
@MainActor
enum ClaudeConfigInstaller {

    enum Target: Sendable, CaseIterable {
        case claudeDesktop
        case claudeCode

        var displayName: String {
            switch self {
            case .claudeDesktop: return "Claude Desktop"
            case .claudeCode:    return "Claude Code"
            }
        }

        var configDirectory: URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            switch self {
            case .claudeDesktop:
                return home.appendingPathComponent("Library/Application Support/Claude")
            case .claudeCode:
                return home
            }
        }

        var configFileName: String {
            switch self {
            case .claudeDesktop: return "claude_desktop_config.json"
            case .claudeCode:    return ".claude.json"
            }
        }

        /// Used as the key inside the JSON config. Same value for both targets.
        var serverEntryKey: String { "ephemeris" }
    }

    struct InstallResult: Sendable {
        let target: Target
        let configFileURL: URL
        let wasFirstInstall: Bool   // file or key didn't exist before
        let binaryPath: String
    }

    enum InstallError: LocalizedError {
        case helperBinaryMissing
        case userCancelled
        case noFolderSelected
        case configParseFailed(underlying: String)
        case writeFailed(underlying: String)

        var errorDescription: String? {
            switch self {
            case .helperBinaryMissing:
                return "Couldn't locate the bundled Ephemeris MCP helper. Try rebuilding the app from Xcode — the helper is built into Ephemeris.app/Contents/Helpers/ via a Run Script phase."
            case .userCancelled, .noFolderSelected:
                return nil   // cancellation is silent
            case .configParseFailed(let s):
                return "Couldn't parse your existing config file. The file may be malformed JSON. Details: \(s)"
            case .writeFailed(let s):
                return "Couldn't write the config file. Details: \(s)"
            }
        }
    }

    // MARK: - Helper-binary location

    /// Returns the URL of the bundled `ephemeris-mcp` binary, or nil if it's missing.
    /// Checks production location first (inside the .app), then a dev fallback
    /// (the swift package build directory) so we can test the installer before
    /// the Run Script phase lands.
    static func bundledHelperBinary() -> URL? {
        // Production: Ephemeris.app/Contents/Helpers/ephemeris-mcp
        let bundleHelpers = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/ephemeris-mcp")
        if FileManager.default.fileExists(atPath: bundleHelpers.path) {
            return bundleHelpers
        }
        // Dev fallback: walk up from the executable to find tools/ephemeris-mcp/.build/release/
        // Works when running Ephemeris.app from DerivedData while the project tools/ are
        // checked out next to it.
        var search = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = search
                .appendingPathComponent("tools/ephemeris-mcp/.build/release/ephemeris-mcp")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            search = search.deletingLastPathComponent()
        }
        // Last-ditch: a hardcoded path useful only during this development session.
        let devHardcoded = URL(fileURLWithPath:
            "/Users/andrewburwell/Developer/MacObservatory/PHD2-Log-Viewer/tools/ephemeris-mcp/.build/release/ephemeris-mcp")
        if FileManager.default.fileExists(atPath: devHardcoded.path) {
            return devHardcoded
        }
        return nil
    }

    // MARK: - Install entry point

    /// Run the full install for one target. Throws `InstallError.userCancelled`
    /// if the user dismisses the NSOpenPanel without picking a folder.
    /// The helper is strictly read-only (the former allow-writes env toggle was
    /// removed 2026-07-07); annotations are added in the app.
    static func install(_ target: Target) async throws -> InstallResult {
        guard let binaryURL = bundledHelperBinary() else {
            throw InstallError.helperBinaryMissing
        }

        // Open NSOpenPanel pre-positioned at the config folder
        let panel = NSOpenPanel()
        panel.title = "Connect Ephemeris to \(target.displayName)"
        panel.message = "Choose the \(target.displayName) config folder to grant Ephemeris one-time access. We'll add an entry pointing at the helper inside this app and preserve any existing entries."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = target.configDirectory

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            throw InstallError.userCancelled
        }

        let accessGranted = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { folderURL.stopAccessingSecurityScopedResource() }
        }

        let configURL = folderURL.appendingPathComponent(target.configFileName)

        // Read existing JSON, or start with {}
        var rootDict: [String: Any] = [:]
        let wasFirstInstall = !FileManager.default.fileExists(atPath: configURL.path)

        if !wasFirstInstall {
            do {
                let data = try Data(contentsOf: configURL)
                if data.isEmpty {
                    rootDict = [:]
                } else {
                    let parsed = try JSONSerialization.jsonObject(with: data, options: [])
                    guard let dict = parsed as? [String: Any] else {
                        throw InstallError.configParseFailed(underlying: "Root JSON value is not an object")
                    }
                    rootDict = dict
                }
            } catch let err as InstallError {
                throw err
            } catch {
                throw InstallError.configParseFailed(underlying: "\(error)")
            }
        }

        // Ensure mcpServers exists as a dict
        var mcpServers = (rootDict["mcpServers"] as? [String: Any]) ?? [:]
        let alreadyHadKey = mcpServers[target.serverEntryKey] != nil

        // Build the entry. For Claude Desktop we use the stdio "command" form.
        // For Claude Code we use the same shape — it accepts stdio entries too.
        // No env block: the helper is read-only, and re-running Connect scrubs
        // any stale EPHEMERIS_MCP_ALLOW_WRITES from older installs (the helper
        // ignores that variable now regardless).
        let entry: [String: Any] = [
            "command": binaryURL.path
        ]
        mcpServers[target.serverEntryKey] = entry
        rootDict["mcpServers"] = mcpServers

        // Write back atomically, pretty-printed
        do {
            let outData = try JSONSerialization.data(
                withJSONObject: rootDict,
                options: [.prettyPrinted, .sortedKeys]
            )
            // Ensure the parent directory exists
            try FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true
            )
            try outData.write(to: configURL, options: .atomic)
        } catch {
            throw InstallError.writeFailed(underlying: "\(error)")
        }

        return InstallResult(
            target: target,
            configFileURL: configURL,
            wasFirstInstall: wasFirstInstall || !alreadyHadKey,
            binaryPath: binaryURL.path
        )
    }
}
