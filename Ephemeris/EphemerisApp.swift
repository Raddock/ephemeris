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
    @State private var library: EphemerisLibrary? = (try? EphemerisLibrary())

    // v2.0 Phase 8: embedded MCP server listening on localhost. Auto-starts at launch
    // when the library is available. URL is surfaced in the MCP Server preferences pane.
    @State private var mcpServer: MCPEmbeddedServer? = nil

    // Shared coordinator for the bulk-import progress window. The LibraryWindow
    // sets `coordinator.active` and opens the import-progress window; that window
    // reads the active importer back out via @Environment.
    @State private var importCoordinator = ImportCoordinator()

    init() {
        // Initialize TipKit at launch so the library-discovery tip is ready when the
        // third NightRecord lands.
        LibraryDiscoveryTipBootstrap.configure()
    }

    var body: some Scene {
        DocumentGroup(viewing: GuideLogDocument.self) { file in
            ContentView(document: file.document)
                .environment(rigProfileStore)
                .environment(\.ephemerisLibrary, library)
                .environment(\.importCoordinator, importCoordinator)
                .environment(mcpServer)
                .task {
                    if mcpServer == nil, let library {
                        let server = MCPEmbeddedServer(library: library)
                        server.start()
                        mcpServer = server
                    }
                }
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
                Button("Library") {
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
                .help("Opens the Library window. Use the Import button there to choose a folder of PHD2 logs.")
            }
        }

        Window("About Ephemeris", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)

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
        WindowGroup("Library", id: "library") {
            LibraryWindow()
                .environment(rigProfileStore)
                .environment(\.ephemerisLibrary, library)
                .environment(\.importCoordinator, importCoordinator)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 720)
        .defaultPosition(.center)

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
