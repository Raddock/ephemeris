//
//  CalibrationHeaderParser.swift
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

/// Extracts structured fields from a calibration section's accumulated header
/// lines. The reference C++ parser in agalasso/phdlogview reads a small subset
/// of these for its UI; we pull everything useful for the inspector.
nonisolated enum CalibrationHeaderParser {

    static func parse(_ lines: [String]) -> CalibrationDetails {
        var d = CalibrationDetails()
        for line in lines {
            apply(line, into: &d)
        }
        return d
    }

    static func apply(_ line: String, into d: inout CalibrationDetails) {
        if let v = doubleAfter("Pixel scale = ", in: line) {
            d.pixelScale = v
        }
        if let v = intAfter("Exposure = ", in: line) {
            d.exposureMs = v
        }
        if let v = intAfter("Calibration Step = ", in: line) {
            d.calibrationStepMs = v
        }
        if let v = intAfter("Calibration Distance = ", in: line) {
            d.calibrationDistancePx = v
        }
        if line.contains("Assume orthogonal axes = ") {
            d.assumeOrthogonalAxes = line.contains("Assume orthogonal axes = yes")
        }
        if let v = doubleAfter("RA Guide Speed = ", in: line) {
            d.raGuideSpeedArcsecPerSec = v
        }
        if let v = doubleAfter("Dec Guide Speed = ", in: line) {
            d.decGuideSpeedArcsecPerSec = v
        }
        if line.contains("Dec = "), let dec = doubleAfter("Dec = ", in: line) {
            d.declinationRad = dec * .pi / 180.0
        }
        if let v = doubleAfter("Hour angle = ", in: line) {
            d.hourAngleHours = v
        }
        if let r = line.range(of: "Pier side = ") {
            let rest = line[r.upperBound...]
            if let comma = rest.firstIndex(of: ",") {
                d.pierSide = String(rest[..<comma])
            } else {
                d.pierSide = String(rest)
            }
        }
        if line.hasPrefix("Lock position = ") {
            // "Lock position = 99.284, 671.087, Star position = ..."
            let rest = line.dropFirst("Lock position = ".count)
            let parts = rest.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: true)
            if parts.count >= 2,
               let x = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let y = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                d.lockPositionX = x
                d.lockPositionY = y
            }
        }
        // Per-direction completion lines, e.g.:
        //   "West calibration complete. Angle = 3.6 deg, Rate = 13.016 px/sec, Parity = Even"
        for dir in [CalibrationEntry.Direction.west, .east, .north, .south] {
            let prefix = "\(dirWord(dir)) calibration complete"
            if line.hasPrefix(prefix) {
                let angle = doubleAfter("Angle = ", in: line)
                let rate  = doubleAfter("Rate = ", in: line)
                let parity = stringAfter("Parity = ", in: line)
                if let a = angle, let r = rate {
                    d.legCompletions[dir] = LegCompletion(
                        angleDeg: a, ratePxPerSec: r, parity: parity
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private static func dirWord(_ d: CalibrationEntry.Direction) -> String {
        switch d {
        case .west:  return "West"
        case .east:  return "East"
        case .north: return "North"
        case .south: return "South"
        case .backlash: return "Backlash"
        }
    }

    private static func doubleAfter(_ key: String, in line: String) -> Double? {
        guard let r = line.range(of: key) else { return nil }
        return scanDouble(line[r.upperBound...])
    }

    private static func intAfter(_ key: String, in line: String) -> Int? {
        guard let r = line.range(of: key) else { return nil }
        var s = ""
        for c in line[r.upperBound...] {
            if c.isNumber || c == "-" { s.append(c) } else { break }
        }
        return Int(s)
    }

    private static func stringAfter(_ key: String, in line: String) -> String? {
        guard let r = line.range(of: key) else { return nil }
        let rest = line[r.upperBound...]
        var out = ""
        for c in rest {
            if c == "," || c == "\n" || c == "\r" { break }
            out.append(c)
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
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
