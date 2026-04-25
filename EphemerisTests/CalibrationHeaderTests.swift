//
//  CalibrationHeaderTests.swift
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
import Testing
@testable import Ephemeris

struct CalibrationHeaderTests {

    static let realistic: [String] = [
        "Equipment Profile = Edge-10m",
        "Pixel scale = 0.62 arc-sec/px, Binning = 1, Focal length = 1960 mm",
        "Camera = ZWO ASI174MM Mini (ASCOM), full size = 1936 x 1216, have dark, dark dur = 5000",
        "Exposure = 5000 ms",
        "Mount = 10Micron, Calibration Step = 250 ms, Calibration Distance = 33 px, Assume orthogonal axes = no",
        "RA Guide Speed = 7.5 a-s/s, Dec Guide Speed = 7.5 a-s/s",
        "RA = 10.32 hr, Dec = -1.5 deg, Hour angle = -0.31 hr, Pier side = West, Rotator pos = N/A",
        "Lock position = 99.284, 671.087, Star position = 99.165, 670.923, HFD = 5.44 px",
        "West calibration complete. Angle = 3.6 deg, Rate = 13.016 px/sec, Parity = Even",
        "North calibration complete. Angle = 93.2 deg, Rate = 16.500 px/sec, Parity = Odd",
    ]

    @Test func parsesPixelScaleAndExposure() {
        let d = CalibrationHeaderParser.parse(Self.realistic)
        #expect(abs((d.pixelScale ?? 0) - 0.62) < 1e-9)
        #expect(d.exposureMs == 5000)
    }

    @Test func parsesCalStepAndDistance() {
        let d = CalibrationHeaderParser.parse(Self.realistic)
        #expect(d.calibrationStepMs == 250)
        #expect(d.calibrationDistancePx == 33)
        #expect(d.assumeOrthogonalAxes == false)
    }

    @Test func parsesGuideSpeedsAndDeclination() {
        let d = CalibrationHeaderParser.parse(Self.realistic)
        #expect(abs((d.raGuideSpeedArcsecPerSec ?? 0) - 7.5) < 1e-9)
        #expect(abs((d.decGuideSpeedArcsecPerSec ?? 0) - 7.5) < 1e-9)
        #expect(abs((d.declinationRad ?? 0) - (-1.5 * .pi / 180.0)) < 1e-6)
        #expect(d.pierSide == "West")
    }

    @Test func parsesLockPosition() {
        let d = CalibrationHeaderParser.parse(Self.realistic)
        #expect(abs((d.lockPositionX ?? 0) - 99.284) < 1e-3)
        #expect(abs((d.lockPositionY ?? 0) - 671.087) < 1e-3)
    }

    @Test func parsesLegCompletions() {
        let d = CalibrationHeaderParser.parse(Self.realistic)
        let west = d.legCompletions[.west]
        let north = d.legCompletions[.north]
        #expect(west != nil)
        #expect(north != nil)
        #expect(abs((west?.angleDeg ?? 0) - 3.6) < 1e-9)
        #expect(abs((west?.ratePxPerSec ?? 0) - 13.016) < 1e-9)
        #expect(west?.parity == "Even")
        #expect(abs((north?.angleDeg ?? 0) - 93.2) < 1e-9)
    }

    @Test func computesOrthogonalityErrorNearZeroForOrthogonalLegs() {
        // West=3.6° and North=93.6° → difference = 90° → orthogonality error = 0
        let d = CalibrationHeaderParser.parse([
            "West calibration complete. Angle = 3.6 deg, Rate = 13.016 px/sec, Parity = Even",
            "North calibration complete. Angle = 93.6 deg, Rate = 16.500 px/sec, Parity = Odd",
        ])
        let ortho = d.orthogonalityErrorDeg
        #expect(ortho != nil)
        #expect(abs((ortho ?? 999)) < 1e-9)
    }

    @Test func computesOrthogonalityErrorForSkewedAxes() {
        // West=0° and North=85° → difference = 85° → orthogonality error = 5°
        let d = CalibrationHeaderParser.parse([
            "West calibration complete. Angle = 0 deg, Rate = 10 px/sec, Parity = Even",
            "North calibration complete. Angle = 85 deg, Rate = 10 px/sec, Parity = Odd",
        ])
        #expect(abs((d.orthogonalityErrorDeg ?? 0) - 5.0) < 1e-9)
    }
}
