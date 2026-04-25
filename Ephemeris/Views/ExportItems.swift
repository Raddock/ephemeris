//
//  ExportItems.swift
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
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// CSV payload that the share sheet treats as a `.csv` document.
struct CSVExportItem: Transferable {
    let content: String
    let suggestedName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { item in
            item.content.data(using: .utf8) ?? Data()
        }
        .suggestedFileName { $0.suggestedName }
    }
}

/// PNG payload for sharing a rendered chart image.
struct PNGExportItem: Transferable {
    let image: NSImage
    let suggestedName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard let tiff = item.image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.coderInvalidValue)
            }
            return png
        }
        .suggestedFileName { $0.suggestedName }
    }
}

/// Renders an arbitrary SwiftUI view to a retina NSImage at the given size.
@MainActor
func renderImage<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2.0) -> NSImage? {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = scale
    return renderer.nsImage
}
