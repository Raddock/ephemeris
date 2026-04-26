//
//  PHD2LogSignature.swift
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

import Foundation

/// Cheap head-of-file content classifier used as a gatekeeper before
/// committing to a full parse. Only the first few KB are inspected.
enum PHD2LogSignature {

    enum Verdict: Equatable {
        /// `PHD2 version …` banner found at file start. Definitely a PHD2 log.
        case confirmed
        /// No banner, but at least one PHD2 section delimiter or column header
        /// is recognized. Probably a PHD2 log fragment or a log with a stripped header.
        case likely
        /// Text content with no PHD2 markers.
        case notPHD2
        /// Contains NUL bytes in the inspected window — almost certainly a binary file.
        case binary
    }

    /// Inspect at most `maxBytes` (default 4096) of the file's contents and
    /// return a verdict. Designed to be safe to call on partial reads.
    static func classify(_ data: Data, maxBytes: Int = 4096) -> Verdict {
        let head = data.prefix(maxBytes)

        // 1. Empty data: no PHD2 evidence and nothing to parse — treat as not PHD2.
        if head.isEmpty { return .notPHD2 }

        // 2. Binary detection: any NUL byte in the inspected window. Real PHD2
        // logs are 7-bit ASCII / UTF-8 text and never contain NULs.
        if head.contains(0) { return .binary }

        // 3. Decode as UTF-8; on failure, treat as binary.
        guard let text = String(data: head, encoding: .utf8) else { return .binary }

        // 4. Banner is the strongest signal.
        if text.hasPrefix("PHD2 version ") { return .confirmed }

        // Tolerate leading whitespace on the first line. (PHD2 itself never
        // writes a BOM, so we don't try to strip U+FEFF; a hypothetical
        // BOM-prefixed file would still classify as `.likely` via the
        // section-marker fallback below.)
        let firstLine = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        if firstLine.trimmingCharacters(in: .whitespaces).hasPrefix("PHD2 version ") {
            return .confirmed
        }

        // 5. Fallback: look for any structural marker that uniquely identifies
        // a PHD2 log section.
        let markers = [
            "Guiding Begins at ",
            "Calibration Begins at ",
            "Frame,Time,mount",
            "Direction,Step,dx,dy",
        ]
        for marker in markers where text.contains(marker) {
            return .likely
        }

        return .notPHD2
    }

    /// Convenience for the common case: feed the whole file's `Data` and let
    /// the function decide how much to inspect.
    static func classify(_ data: Data) -> Verdict {
        classify(data, maxBytes: 4096)
    }
}
