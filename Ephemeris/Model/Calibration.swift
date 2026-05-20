//
//  Calibration.swift
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

struct Calibration: Sendable, Identifiable {
    let id = UUID()
    var startedAt: Date?
    var device: GuideDevice.Kind = .mount
    var rawHeader: [String] = []
    var entries: [CalibrationEntry] = []
    var details: CalibrationDetails = CalibrationDetails()
}

struct CalibrationDetails: Sendable, Equatable {
    var pixelScale: Double?              // arcsec/px
    var exposureMs: Int?
    var calibrationStepMs: Int?
    var calibrationDistancePx: Int?
    var assumeOrthogonalAxes: Bool?
    var raGuideSpeedArcsecPerSec: Double?
    var decGuideSpeedArcsecPerSec: Double?
    var declinationRad: Double?
    var hourAngleHours: Double?
    var pierSide: String?
    var lockPositionX: Double?
    var lockPositionY: Double?
    var legCompletions: [CalibrationEntry.Direction: LegCompletion] = [:]

    /// |delta(west, north)| − 90°; positive = mount axes deviate from orthogonality.
    /// Returns nil unless both legs reported angles.
    nonisolated var orthogonalityErrorDeg: Double? {
        guard let w = legCompletions[.west]?.angleDeg,
              let n = legCompletions[.north]?.angleDeg else { return nil }
        // Smallest signed angular difference on a 360° circle, then unsigned distance from 90°.
        var d = (w - n).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return abs(abs(d) - 90.0)
    }
}

struct LegCompletion: Sendable, Equatable {
    var angleDeg: Double
    var ratePxPerSec: Double
    var parity: String?
}

struct CalibrationEntry: Sendable, Identifiable {
    let id = UUID()
    var direction: Direction
    var step: Int
    var dx: Double
    var dy: Double

    enum Direction: String, Sendable {
        case west, east, north, south, backlash

        init?(token: String) {
            switch token {
            case "West", "Left": self = .west
            case "East": self = .east
            case "North", "Up": self = .north
            case "South": self = .south
            case "Backlash": self = .backlash
            default: return nil
            }
        }

        static func device(forToken token: String) -> GuideDevice.Kind? {
            switch token {
            case "Left", "Up": return .ao
            case "West", "East", "North", "South", "Backlash": return .mount
            default: return nil
            }
        }
    }
}
