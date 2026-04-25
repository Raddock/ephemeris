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

    var body: some Scene {
        DocumentGroup(viewing: GuideLogDocument.self) { file in
            ContentView(document: file.document)
        }
        .commands {
            // Replace the system About panel with our custom window so we can
            // show a larger icon, tagline, and Documentation/Support links.
            CommandGroup(replacing: .appInfo) {
                Button("About Ephemeris") {
                    openWindow(id: "about")
                }
            }
        }

        Window("About Ephemeris", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
    }
}
