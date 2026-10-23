//
//  ASIAirFormatTests.swift
//  EphemerisTests
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

/// ZWO's ASIAir writes a "PHD2 compatible" guide log that differs from PHD2's
/// own in a few header lines: no PHD2 version number in the banner, a blank
/// Equipment Profile, no `RA = ` field on the pointing line, no `Norm rates`
/// line, and no `Guiding Ends` after the last session. The values below are
/// synthetic; the line shapes follow a real ASIAir log (October 2026).
struct ASIAirFormatTests {

    static let log = """
    PHD2 version, Log version 2.5. Log enabled at 2026-10-16 19:30:46

    Calibration Begins at 2026-10-16 19:30:46
    Equipment Profile =
    Camera = ZWO ASI120MC-S
    Exposure = 1500 ms
    Pixel scale = 6.45 arc-sec/px, Binning = 1, Focal length = 120 mm
    Mount = EQMod Mount, Calibration Step = 2000 ms, Assume orthogonal axes = no
    Dec = 15.5 deg, Hour angle = 0.15 hr, Pier side = West, Rotator pos = Unknown
    Lock position = 76.500, 209.600, Star position = 76.700, 210.300, HFD = 3.70 px
    Direction,Step,dx,dy,x,y,Dist
    West,0,0.000,0.000,77.000,211.000,0.000
    West,1,-4.000,-0.200,81.000,211.200,4.005
    West calibration complete. Angle = -178.0 deg, Rate = 2.300 px/sec, Parity = Even
    North,0,0.000,0.000,85.000,215.000,0.000
    North,1,0.500,2.700,84.500,212.300,2.746
    North calibration complete. Angle = -101.0 deg, Rate = 1.500 px/sec, Parity = Even
    Calibration complete, mount = EQMod Mount.

    Guiding Begins at 2026-10-16 19:32:59
    Dither = both axes, Dither scale = 1.000, Image noise reduction = none, Guide-frame time lapse = 0, Server enabled
    Pixel scale = 6.45 arc-sec/px, Binning = 1, Focal length = 120 mm
    Search region = 50 px, Star mass tolerance = 50.0%
    Equipment Profile =
    Camera = ZWO ASI120MC-S, gain = 66, full size = 1280 x 960, no dark, no defect map, pixel size = 3.8 um
    Exposure = 1500 ms
    Mount = EQMod Mount,  connected, guiding enabled, xAngle = -178.0, xRate = 2.300, yAngle = -101.0, yRate = 1.500, parity = +/+,
    X guide algorithm = Hysteresis, Hysteresis = 0.100, Aggression = 0.750, Minimum move = 0.100
    Y guide algorithm = Resist Switch, Minimum move = 0.100 Aggression = 85% FastSwitch = enabled
    Backlash comp = disabled, pulse = 0 ms
    Calibration step = phdlab_placeholder, Max RA duration = 2000, Max DEC duration = 2000, DEC guide mode = Auto
    RA Guide Speed = 13.5 a-s/s, Dec Guide Speed = 13.5 a-s/s, Cal Dec = 15.6, Last Cal Issue = Orthogonality, Timestamp = Unknown
    Dec = 15.6 deg, Hour angle = 0.19 hr, Pier side = West, Rotator pos = Unknown
    Lock position = 76.500, 209.600, Star position = 85.300, 208.300, HFD = 3.67 px
    Frame,Time,mount,dx,dy,RARawDistance,DECRawDistance,RAGuideDistance,DECGuideDistance,RADuration,RADirection,DECDuration,DECDirection,XStep,YStep,StarMass,SNR,ErrorCode
    INFO: SETTLING STATE CHANGE, Settling started
    1,1.250,"Mount",-0.100,0.400,0.100,-0.400,0.000,-0.300,0,,200,N,,,1500,27.00,0
    2,2.500,"Mount",-0.200,0.500,0.200,-0.500,0.100,-0.400,40,W,250,N,,,1600,28.00,0
    INFO: SETTLING STATE CHANGE, Settling failed
    Guiding Ends at 2026-10-16 19:36:56

    Guiding Begins at 2026-10-16 19:38:56
    Pixel scale = 6.45 arc-sec/px, Binning = 1, Focal length = 120 mm
    Equipment Profile =
    Exposure = 1500 ms
    Mount = EQMod Mount,  connected, guiding enabled, xAngle = -178.0, xRate = 2.040, yAngle = -101.0, yRate = 1.500, parity = +/+,
    Dec = 31.2 deg, Hour angle = -0.93 hr, Pier side = East, Rotator pos = Unknown
    Frame,Time,mount,dx,dy,RARawDistance,DECRawDistance,RAGuideDistance,DECGuideDistance,RADuration,RADirection,DECDuration,DECDirection,XStep,YStep,StarMass,SNR,ErrorCode
    1,1.250,"Mount",-0.100,0.400,0.100,-0.400,0.000,-0.300,0,,200,N,,,1500,27.00,0
    2,2.500,"Mount",-0.200,0.500,0.200,-0.500,0.100,-0.400,40,W,250,N,,,1600,28.00,0
    3,3.750,"Mount",-0.150,0.450,0.150,-0.450,0.050,-0.350,30,W,220,N,,,1550,27.50,0
    """

    // MARK: - Signature

    @Test func bannerWithoutVersionNumberIsConfirmed() {
        #expect(PHD2LogSignature.classify(Data(Self.log.utf8)) == .confirmed)
    }

    @Test func unrelatedPHD2PrefixIsNotABanner() {
        // Only a space or a comma may follow "PHD2 version"; anything else is not
        // the banner, and with no section markers the file is not a guide log.
        let text = "PHD2 versionless notes\nnothing else here\n"
        #expect(PHD2LogSignature.classify(Data(text.utf8)) == .notPHD2)
    }

    // MARK: - Parser

    @Test func parsesBannerWithEmptyPHD2Version() {
        let log = GuideLogParser.parse(Self.log)
        #expect(log.phdVersion == "")
        #expect(log.logVersion.hasPrefix("2.5"))
    }

    @Test func parsesCalibrationAndBothSessions() {
        let log = GuideLogParser.parse(Self.log)
        #expect(log.calibrations.count == 1)
        #expect(log.guideSessions.count == 2)
        // The last session has no "Guiding Ends" line; end of file closes it.
        #expect(log.guideSessions.map(\.entries.count) == [2, 3])
        #expect(log.guideSessions.allSatisfy { $0.malformedFieldCount == 0 })
    }

    // MARK: - Pointing line without RA

    @Test func pointingLineWithoutRAStillYieldsDecHourAngleAndPierSide() throws {
        let sessions = GuideLogParser.parse(Self.log).guideSessions
        let first = sessions[0].headerProperties
        #expect(first.raHours == nil)
        #expect(try #require(first.decDegrees) == 15.6)
        #expect(try #require(first.hourAngleHours) == 0.19)
        #expect(first.pierSide == "West")
        #expect(first.hasPointingFix == false)

        let second = sessions[1].headerProperties
        #expect(try #require(second.decDegrees) == 31.2)
        #expect(try #require(second.hourAngleHours) == -0.93)
        #expect(second.pierSide == "East")
    }

    @Test func pointingLineWithRAStillParsesAllFields() throws {
        let props = SessionHeaderProperties(rawHeader: [
            "RA = 12.64 hr, Dec = 13.0 deg, Hour angle = -2.36 hr, Pier side = West, Rotator pos = N/A, Alt = 52.4 deg, Az = 112.3 deg",
        ])
        #expect(try #require(props.raHours) == 12.64)
        #expect(try #require(props.decDegrees) == 13.0)
        #expect(try #require(props.hourAngleHours) == -2.36)
        #expect(props.pierSide == "West")
        #expect(props.hasPointingFix)
    }

    @Test func otherDecFieldsAreNotMistakenForPointing() {
        // "Norm rates ... Dec = 10.2\"/s" and "Cal Dec = 15.6" carry a Dec value
        // but are not the pointing line.
        let props = SessionHeaderProperties(rawHeader: [
            #"Norm rates RA = 8.3"/s @ dec 0, Dec = 10.2"/s; ortho.err. = 12.2 deg"#,
            "RA Guide Speed = 13.5 a-s/s, Dec Guide Speed = 13.5 a-s/s, Cal Dec = 15.6, Last Cal Issue = None",
        ])
        #expect(props.decDegrees == nil)
        #expect(props.raHours == nil)
        #expect(props.pierSide == nil)
    }
}
