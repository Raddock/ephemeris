//
//  WindowSubtitleSetter.swift
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

import AppKit
import SwiftUI

/// Overrides macOS's auto-applied " — Locked" suffix on read-only document
/// windows by writing directly to `NSWindow.subtitle` after layout.
///
/// `.navigationSubtitle` only appends to the OS-provided lock indicator; this
/// is the only reliable way to clear it for a `FileDocument` that's read-only
/// by design.
struct WindowSubtitleSetter: NSViewRepresentable {
    let subtitle: String

    func makeNSView(context: Context) -> NSView {
        let view = SubtitleProbeView()
        view.subtitle = subtitle
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let probe = nsView as? SubtitleProbeView else { return }
        probe.subtitle = subtitle
        DispatchQueue.main.async {
            probe.window?.subtitle = subtitle
        }
    }

    final class SubtitleProbeView: NSView {
        var subtitle: String = ""
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.subtitle = subtitle
        }
    }
}
