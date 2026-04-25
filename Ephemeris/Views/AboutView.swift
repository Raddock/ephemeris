//
//  AboutView.swift
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
import AppKit

/// Custom About panel matching the visual style of Laminar / Meridian. Replaces
/// the default macOS About panel via a `CommandGroup(replacing: .appInfo)` in
/// the app scene, opened as a non-resizable utility window.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 160, height: 160)
                .padding(.top, 36)
                .padding(.bottom, 22)

            Text(appName)
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 6)

            Text("Version \(versionString)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)

            Text(tagline)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            Text(copyright)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 22)

            Divider()
                .padding(.horizontal, 32)
                .padding(.bottom, 18)

            HStack(spacing: 36) {
                Button("Documentation") {
                    NSApplication.shared.showHelp(nil)
                }
                .buttonStyle(.link)
                Link("Support", destination: supportURL)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                Text("Acknowledgments")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Based on phdlogview by Andy Galasso")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 28)
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Bundle metadata

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Ephemeris"
    }

    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 Andrew Burwell"
    }

    private let tagline = "Read your PHD2 guide logs the Mac way"

    private let supportURL = URL(string: "https://github.com/Raddock/ephemeris/issues")!

    /// Pull the app icon directly from `NSApp` so the live Liquid Glass / legacy
    /// rendering matches whatever macOS is currently displaying.
    private var appIcon: NSImage {
        if let img = NSImage(named: NSImage.applicationIconName) {
            return img
        }
        return NSApp.applicationIconImage ?? NSImage()
    }
}

