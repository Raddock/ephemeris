//
//  HeaderParser.swift
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

nonisolated enum HeaderParser {

    static func apply(_ line: String, to session: inout GuideSession, cursor: inout HeaderCursorState) {
        if line.hasPrefix("Mount = ") {
            cursor.device = .mount
            session.mount.kind = .mount
            session.mount.name = nameAfter(prefix: "Mount = ", in: line)
            session.mount.guidingEnabled = line.contains(", guiding enabled,")
            applyAxisRates(line, to: &session.mount)
            applyMaxDurations(line, to: &session.mount)
            return
        }
        if line.hasPrefix("AO = ") {
            cursor.device = .ao
            var ao = session.ao ?? GuideDevice(kind: .ao)
            ao.name = nameAfter(prefix: "AO = ", in: line)
            applyAxisRates(line, to: &ao)
            session.ao = ao
            return
        }
        if line.hasPrefix("Pixel scale = ") {
            session.pixelScale = firstDouble(in: line) ?? session.pixelScale
            return
        }
        if line.contains("Dec = "), let dec = doubleAfter("Dec = ", in: line) {
            session.declination = dec * .pi / 180.0
            return
        }
        if line.hasPrefix("X guide algorithm = ") {
            cursor.axis = "X"
            switch cursor.device {
            case .mount: session.mount.xGuideAlgorithm = nameAfter(prefix: "X guide algorithm = ", in: line)
            case .ao: session.ao?.xGuideAlgorithm = nameAfter(prefix: "X guide algorithm = ", in: line)
            }
            return
        }
        if line.hasPrefix("Y guide algorithm = ") {
            cursor.axis = "Y"
            switch cursor.device {
            case .mount: session.mount.yGuideAlgorithm = nameAfter(prefix: "Y guide algorithm = ", in: line)
            case .ao: session.ao?.yGuideAlgorithm = nameAfter(prefix: "Y guide algorithm = ", in: line)
            }
            return
        }
        if let mm = doubleAfter("Minimum move = ", in: line) {
            switch (cursor.device, cursor.axis) {
            case (.mount, "X"): session.mount.minMoveX = mm
            case (.mount, "Y"): session.mount.minMoveY = mm
            case (.ao, "X"): session.ao?.minMoveX = mm
            case (.ao, "Y"): session.ao?.minMoveY = mm
            default: break
            }
            return
        }
    }

    private static func nameAfter(prefix: String, in line: String) -> String {
        let rest = line.dropFirst(prefix.count)
        if let comma = rest.firstIndex(of: ",") { return String(rest[..<comma]) }
        return String(rest)
    }

    private static func applyAxisRates(_ line: String, to dev: inout GuideDevice) {
        if let v = doubleAfter("xAngle = ", in: line) { dev.xAngle = v }
        if let v = doubleAfter("xRate = ", in: line) { dev.xRate = v }
        if let v = doubleAfter("yAngle = ", in: line) { dev.yAngle = v }
        if let v = doubleAfter("yRate = ", in: line) { dev.yRate = v }
        // Old logs stored rates in px/ms — heuristic from logparser.cpp.
        if dev.xRate > 0, dev.xRate < 0.05 { dev.xRate *= 1000 }
        if dev.yRate > 0, dev.yRate < 0.05 { dev.yRate *= 1000 }
    }

    private static func applyMaxDurations(_ line: String, to dev: inout GuideDevice) {
        if let v = intAfter("Max RA duration = ", in: line) { dev.maxRADuration = v }
        if let v = intAfter("Max DEC duration = ", in: line) { dev.maxDecDuration = v }
    }

    private static func doubleAfter(_ key: String, in line: String) -> Double? {
        guard let r = line.range(of: key) else { return nil }
        let tail = line[r.upperBound...]
        return scanDouble(tail)
    }

    private static func intAfter(_ key: String, in line: String) -> Int? {
        guard let r = line.range(of: key) else { return nil }
        let tail = line[r.upperBound...]
        var s = ""
        for c in tail {
            if c.isNumber || c == "-" { s.append(c) } else { break }
        }
        return Int(s)
    }

    private static func firstDouble(in line: String) -> Double? {
        var seenDigit = false
        var s = ""
        for c in line {
            if c.isNumber { s.append(c); seenDigit = true; continue }
            if c == "." || c == "-" || c == "+" || c.lowercased() == "e" { s.append(c); continue }
            if seenDigit { break }
            s = ""
        }
        return Double(s.trimmingCharacters(in: .whitespaces))
    }

    private static func scanDouble<S: StringProtocol>(_ s: S) -> Double? {
        var out = ""
        var seenDigit = false
        for c in s {
            if c == " " || c == "\t" {
                if seenDigit { break } else { continue }
            }
            if c.isNumber { out.append(c); seenDigit = true; continue }
            if c == "-" || c == "+", out.isEmpty { out.append(c); continue }
            if c == "." || c.lowercased() == "e" { out.append(c); continue }
            if seenDigit { break }
            return nil
        }
        return Double(out)
    }
}

nonisolated struct HeaderCursorState {
    var device: GuideDevice.Kind = .mount
    var axis: Character = "X"
}
