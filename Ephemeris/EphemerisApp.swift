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

@main
struct EphemerisApp: App {
    @Environment(\.openWindow) private var openWindow

    // v2.0 Phase 1: app-wide RigProfileStore. JSON-sidecar persistence until Phase 3
    // promotes it to SwiftData. Injected into the environment so any document-window
    // view can read profile data.
    @State private var rigProfileStore = RigProfileStore()

    // v2.0 Phase 3: SwiftData library backing the multi-night surface (Phase 6+).
    // Auto-ingest of opened documents happens in ContentView when both the rig
    // profile and the parsed log are available. Construction failure is swallowed
    // for now — Phase 3 will surface a recovery UI when the store can't be opened.
    @State private var library: EphemerisLibrary?

    // v2.0 Phase 8: embedded MCP server listening on localhost. Created eagerly so
    // the env object is populated when macOS restores scenes (e.g. the MCP Server
    // window) on launch — otherwise that view crashes with a missing-env-object.
    @State private var mcpServer: MCPEmbeddedServer?

    // Shared coordinator for the bulk-import progress window. The LibraryWindow
    // sets `coordinator.active` and opens the import-progress window; that window
    // reads the active importer back out via @Environment.
    @State private var importCoordinator = ImportCoordinator()

    init() {
        // Initialize TipKit at launch so the library-discovery tip is ready when the
        // third NightRecord lands.
        LibraryDiscoveryTipBootstrap.configure()

        // App Shortcuts (Phase 6) post notifications that EphemerisApp wires into
        // openWindow + an @AppStorage rig selection. We register the listener on
        // the main actor since it touches AppKit on dispatch.
        AppShortcutBridge.shared.registerOnce()

        let library = try? EphemerisLibrary()
        _library = State(initialValue: library)
        if let library {
            let server = MCPEmbeddedServer(library: library)
            server.start()
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
            LibraryWindow()
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
