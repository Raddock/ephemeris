//
//  InfoCoalescer.swift
//  Ephemeris
//
//  Copyright (C) 2026 Andrew Burwell
//
//  This file derives behavioral logic from logparser.cpp / logparser.h
//  in agalasso/phdlogview, Copyright (C) 2016-2020 Andy Galasso,
//  licensed under GPLv3. Original: https://github.com/agalasso/phdlogview
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

/// Categorizes an info line into a kind useful for filtering / coloring in the UI.
enum InfoKind: Sendable, Equatable {
    case settlingStarted
    case settlingComplete
    case settlingFailed
    case dither
    case mountGeometryChange
    case calibrationRejected
    case loopingExposures
    case starLost
    case frameDropped
    case parameterChange   // "key = value"
    case setLockPos
    case serverEvent       // "Server received ..."
    case other

    static func classify(_ text: String) -> InfoKind {
        if text.hasPrefix("Settling started") { return .settlingStarted }
        if text.hasPrefix("Settling complete") { return .settlingComplete }
        if text.hasPrefix("Settling failed") { return .settlingFailed }
        if text.hasPrefix("DITHER") { return .dither }
        if text.hasPrefix("MOUNT_GEOMETRY_CHANGE") { return .mountGeometryChange }
        if text.hasPrefix("CALIBRATION_REJECTED") { return .calibrationRejected }
        if text.hasPrefix("LOOPING EXPOSURES") { return .loopingExposures }
        if text.hasPrefix("Star lost") { return .starLost }
        if text.hasPrefix("Frame dropped") { return .frameDropped }
        if text.hasPrefix("SET LOCK POS") { return .setLockPos }
        if text.hasPrefix("Server received") { return .serverEvent }
        // Heuristic: a "key=value" or "key = value" line that doesn't match above is a param change.
        if text.contains("=") { return .parameterChange }
        return .other
    }
}

extension InfoEntry {
    var kind: InfoKind { InfoKind.classify(text) }

    /// `"key"` for a parameter-change entry like `"MultiStar = true"`. Nil otherwise.
    var parameterKey: String? {
        guard kind == .parameterChange else { return nil }
        guard let eq = text.firstIndex(of: "=") else { return nil }
        return text[..<eq].trimmingCharacters(in: .whitespaces)
    }
}

enum InfoCoalescer {

    /// Apply the three coalescing rules from logparser.cpp:
    ///
    /// 1. **Repeats**: identical text on consecutive frames → merge into one entry
    ///    with `repeats` incremented.
    /// 2. **Param replace**: when an entry on the same frame has the same
    ///    `key=` prefix as the previous entry, replace the previous one rather
    ///    than appending.
    /// 3. **Lock-pos override**: a `SET LOCK POS` followed on the same frame by
    ///    a `DITHER` is replaced (PHD2 always emits both, dither is the useful one).
    static func coalesce(_ infos: [InfoEntry]) -> [InfoEntry] {
        var out: [InfoEntry] = []
        out.reserveCapacity(infos.count)

        for info in infos {
            // Rule 1: repeats — same exact text on consecutive frames (any frame gap > 0).
            if let last = out.last,
               last.text == info.text,
               last.frame != info.frame {
                var merged = last
                merged.repeats += 1
                merged.frame = info.frame   // bump to most recent frame
                out[out.count - 1] = merged
                continue
            }

            // Rules 2 and 3 only fire when this entry is on the same frame as the previous one.
            if let last = out.last, last.frame == info.frame {
                // Rule 3: SET LOCK POS → DITHER replacement.
                if last.kind == .setLockPos, info.kind == .dither {
                    out[out.count - 1] = info
                    continue
                }
                // Rule 2: same parameter key — replace previous with new value.
                if let lastKey = last.parameterKey,
                   let newKey = info.parameterKey,
                   lastKey == newKey {
                    out[out.count - 1] = info
                    continue
                }
            }

            out.append(info)
        }
        return out
    }
}
