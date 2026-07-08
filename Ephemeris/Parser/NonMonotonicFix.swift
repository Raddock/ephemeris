//
//  NonMonotonicFix.swift
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

nonisolated enum NonMonotonicFix {

    static func apply(to session: GuideSession) -> GuideSession {
        var s = session
        guard s.entries.count >= 2 else { return s }

        // Compute median of positive deltas as the typical sample interval.
        var deltas: [Double] = []
        deltas.reserveCapacity(s.entries.count)
        for i in 1..<s.entries.count {
            let dt = s.entries[i].time - s.entries[i - 1].time
            if dt > 0 { deltas.append(dt) }
        }
        guard !deltas.isEmpty else { return s }
        deltas.sort()
        let median = deltas[deltas.count / 2]

        var offset = 0.0
        var firstJumpFrame: Int? = nil
        for i in 1..<s.entries.count {
            let raw = session.entries[i].time
            let prev = s.entries[i - 1].time
            let dt = (raw + offset) - prev
            if dt < 0 {
                let target = prev + median
                offset += target - (raw + offset)
                if firstJumpFrame == nil { firstJumpFrame = s.entries[i].frame }
            }
            s.entries[i].time = raw + offset
        }

        if let f = firstJumpFrame {
            s.infos.append(InfoEntry(frame: f, text: "Timestamp jumped backwards"))
        }
        return s
    }
}
