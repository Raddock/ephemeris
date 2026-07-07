//
//  EphemerisApp.swift
//  Ephemeris
//
//  Copyright (C) 2026 Andrew Burwell
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI
import Sparkle

@main
struct EphemerisApp: App {
    @Environment(\.openWindow) private var openWindow

    // App-wide RigProfileStore backed by the library's SwiftData container
    // (single owner — the Phase 1 JSON sidecar is imported once and retired).
    // Injected into the environment so any document-window view can read
    // profile data. Constructed in init, after the library opens.
    @State private var rigProfileStore: RigProfileStore

    // v2.0 Phase 3: SwiftData library backing the multi-night surface (Phase 6+).
    // Auto-ingest of opened documents happens in ContentView when both the rig
    // profile and the parsed log are available. When the store fails to open,
    // `libraryOpenError` carries the reason into the Library window's recovery UI.
    @State private var library: EphemerisLibrary?
    @State private var libraryOpenError: String?

    // v2.0 Phase 8: embedded MCP server listening on localhost. Created eagerly so
    // the env object is populated when macOS restores scenes (e.g. the MCP Server
    // window) on launch — otherwise that view crashes with a missing-env-object.
    @State private var mcpServer: MCPEmbeddedServer?

    // Shared coordinator for the bulk-import progress window. The LibraryWindow
    // sets `coordinator.active` and opens the import-progress window; that window
    // reads the active importer back out via @Environment.
    @State private var importCoordinator = ImportCoordinator()

    // Sparkle 2 auto-update. The updater machinery only starts when this build is
    // actually updatable: never inside a test host (XCUITest launches would emit
    // updater log noise and can pop dialogs), and not while SUPublicEDKey is still
    // the placeholder (nothing to verify against until the real key ships — see
    // docs/RELEASE.md). The "Check for Updates…" menu item stays disabled until
    // the updater is started.
    private let updaterController: SPUStandardUpdaterController

    private static var sparkleShouldStart: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !publicKey.isEmpty && !publicKey.hasPrefix("REPLACE-")
    }

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: Self.sparkleShouldStart,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Initialize TipKit at launch so the library-discovery tip is ready when the
        // third NightRecord lands.
        LibraryDiscoveryTipBootstrap.configure()

        // App Shortcuts (Phase 6) post notifications that EphemerisApp wires into
        // openWindow + an @AppStorage rig selection. We register the listener on
        // the main actor since it touches AppKit on dispatch.
        AppShortcutBridge.shared.registerOnce()

        let library: EphemerisLibrary?
        do {
            library = try EphemerisLibrary()
        } catch {
            library = nil
            _libraryOpenError = State(initialValue: error.localizedDescription)
            NSLog("[Library] Store failed to open: %@", error.localizedDescription)
        }
        _library = State(initialValue: library)
        _rigProfileStore = State(initialValue: RigProfileStore(container: library?.container))
        if let library {
            let server = MCPEmbeddedServer(library: library)
            // Opt-in: a local listening socket only opens when the user has
            // enabled it in the MCP Server window (or via the Claude installer).
            server.startIfEnabled()
            _mcpServer = State(initialValue: server)
        }
        // Launch-into-Log-Library is handled declaratively by
        // `.defaultLaunchBehavior` on the scenes below — no runloop hack needed.
    }

    var body: some Scene {
        DocumentGroup(viewing: GuideLogDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                .environment(rigProfileStore)
                .environment(\.ephemerisLibrary, library)
                .environment(\.importCoordinator, importCoordinator)
                .environment(mcpServer)
                .modifier(OpenLibraryOnRequest())
        }
        .commands {
            // Replace the system About panel with our custom window so we can
            // show a larger icon, tagline, and Documentation/Support links.
            CommandGroup(replacing: .appInfo) {
                Button("About Ephemeris") {
                    openWindow(id: "about")
                }
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(after: .appSettings) {
                Button("Rig Profiles…") {
                    openWindow(id: "rigProfiles")
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])
                Button("MCP Server…") {
                    openWindow(id: "mcpServer")
                }
            }
            CommandGroup(after: .windowList) {
                Button("Log Library") {
                    openWindow(id: "library")
                    LibraryDiscoveryTipBootstrap.dismissTip()
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Button("Import Folder of Logs…") {
                    openWindow(id: "library")
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .help("Opens the Log Library window. Use the Import button there to choose a folder of PHD2 logs.")
            }
        }
        // Launch into the Log Library, not an open-file panel — the library is
        // the app's home now; opening a log drills into the document viewer.
        .defaultLaunchBehavior(.suppressed)

        Window("About Ephemeris", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)

        // macOS Settings scene — flat single pane per HIG. Rig editing and the MCP
        // server connector are full management surfaces (list+detail, install panels)
        // and don't fit the Settings shape, so they live as their own Window scenes
        // below. Settings here is for true app-wide preferences only.
        Settings {
            SettingsWindow()
                .environment(\.ephemerisLibrary, library)
                .frame(width: 520)
        }

        Window("Rig Profiles", id: "rigProfiles") {
            RigProfilesWindow()
                .environment(rigProfileStore)
                .environment(\.ephemerisLibrary, library)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 540)
        .defaultPosition(.center)

        Window("MCP Server", id: "mcpServer") {
            MCPServerWindow()
                .environment(mcpServer)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 640, height: 620)
        .defaultPosition(.center)

        // v2.0 Phase 6 — multi-night library. Per design doc §5.2 / §7.1, use WindowGroup
        // (not Window) so the scene can carry a data binding (the active rig).
        WindowGroup("Log Library", id: "library") {
            LibraryWindow(libraryOpenError: libraryOpenError)
                .environment(rigProfileStore)
                .environment(\.ephemerisLibrary, library)
                .environment(\.importCoordinator, importCoordinator)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 720)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.presented)

        // Bulk-import progress window. Standalone Window scene (not a sheet) — macOS
        // sheets were collapsing to ~120×120 in this OS version regardless of .frame
        // hints. A real Window scene gets proper sizing rules.
        Window("Importing PHD2 logs", id: "library-import") {
            LibraryImportWindow()
                .environment(\.importCoordinator, importCoordinator)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 460)
        .defaultPosition(.center)
    }
}

/// Listens for `.ephemerisOpenLibraryWindow` and opens the Library scene.
/// Attached to every document-window content so the notification has a live
/// scene context to call `openWindow` from. Idempotent — SwiftUI's openWindow
/// will focus an existing Library window rather than open a duplicate.
private struct OpenLibraryOnRequest: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .ephemerisOpenLibraryWindow)) { _ in
                openWindow(id: "library")
            }
    }
}
