//
//  ParserTests.swift
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

struct ParserTests {

    static let fixture = """
    PHD2 version 2.6.11, Log version 2.5. Log enabled at 2024-01-15 21:30:00
    Calibration Begins at 2024-01-15 21:31:00
    Mount = "Test Mount", connected, guiding enabled, xAngle = 90.0, xRate = 5.0, yAngle = 0.0, yRate = 5.0
    Pixel scale = 1.500 arc-sec/pixel
    Direction,Step,dx,dy,x,y,Dist
    West,1,0.5,0.0,0.5,0.0,0.5
    West,2,1.0,0.1,1.0,0.1,1.0
    East,3,0.0,0.0,0.0,0.0,0.0
    Calibration complete
    Guiding Begins at 2024-01-15 21:35:00
    Mount = "Test Mount", connected, guiding enabled, xAngle = 90.0, xRate = 5.0, yAngle = 0.0, yRate = 5.0
    Pixel scale = 1.500 arc-sec/pixel
    RA = 5.5 hr, Dec = 45.0 deg, Hour angle = -1.0 hr, Pier side = East
    Frame,Time,mount,dx,dy,RARawDistance,DECRawDistance,RAGuideDistance,DECGuideDistance,RADuration,RADirection,DECDuration,DECDirection,XStep,YStep,StarMass,SNR,ErrorCode
    1,1.000,"Mount",0.10,-0.20,0.10,-0.20,0.05,-0.10,150,W,200,N,,,5000,12.5,0
    2,2.000,"Mount",-0.30,0.40,-0.30,0.40,-0.20,0.30,300,E,250,S,,,5100,11.8,0
    3,3.000,"Mount",0.05,0.05,0.05,0.05,0.00,0.00,0,,0,,,,4900,2.0,3,"Star lost"
    INFO: DITHER by 5.0, 3.0, new lock pos = 100.5, 200.5
    4,4.000,"Mount",0.15,-0.10,0.15,-0.10,0.10,-0.05,100,W,50,N,,,5200,13.0,0
    Guiding Ends
    """

    @Test func parsesVersion() {
        let log = GuideLogParser.parse(Self.fixture)
        #expect(log.phdVersion.hasPrefix("2.6.11"))
    }

    @Test func parsesSectionsInOrder() {
        let log = GuideLogParser.parse(Self.fixture)
        #expect(log.sections.count == 2)
        if case .calibration(let i) = log.sections[0] { #expect(i == 0) } else { Issue.record("first section should be calibration") }
        if case .guide(let i) = log.sections[1] { #expect(i == 0) } else { Issue.record("second section should be guide") }
    }

    @Test func parsesCalibrationEntries() {
        let log = GuideLogParser.parse(Self.fixture)
        #expect(log.calibrations.count == 1)
        let cal = log.calibrations[0]
        #expect(cal.device == .mount)
        #expect(cal.entries.count == 3)
        #expect(cal.entries[0].direction == .west)
        #expect(cal.entries[0].step == 1)
        #expect(cal.entries[2].direction == .east)
    }

    @Test func parsesGuideRowsWithSignedDurations() {
        let log = GuideLogParser.parse(Self.fixture)
        #expect(log.guideSessions.count == 1)
        let s = log.guideSessions[0]
        #expect(s.entries.count == 4)

        let r1 = s.entries[0]
        #expect(r1.frame == 1)
        #expect(r1.raDuration == -150) // W is negative
        #expect(r1.decDuration == 200) // N is positive
        #expect(r1.included)

        let r2 = s.entries[1]
        #expect(r2.raDuration == 300)  // E is positive
        #expect(r2.decDuration == -250) // S is negative
    }

    @Test func parsesFrameDropAndStarLost() {
        let log = GuideLogParser.parse(Self.fixture)
        let s = log.guideSessions[0]
        let r3 = s.entries[2]
        #expect(r3.errorCode == 3)
        #expect(!r3.included)
        #expect(r3.info == "Star lost")
    }

    @Test func parsesPixelScaleAndMountName() {
        let log = GuideLogParser.parse(Self.fixture)
        let s = log.guideSessions[0]
        #expect(abs(s.pixelScale - 1.5) < 0.001)
        #expect(s.mount.name == "\"Test Mount\"")
        #expect(s.mount.guidingEnabled)
        #expect(abs(s.declination - (45.0 * .pi / 180.0)) < 1e-6)
    }

    @Test func recognizesDitherInfo() {
        let log = GuideLogParser.parse(Self.fixture)
        let s = log.guideSessions[0]
        let dither = s.infos.first { $0.text.hasPrefix("DITHER") }
        #expect(dither != nil)
        #expect(dither?.text == "DITHER by 5.0, 3.0")
    }

    @Test func parsesCRLFLineEndings() {
        // Windows-generated PHD2 logs use CRLF. Swift treats `\r\n` as a single
        // grapheme-cluster Character, so naive `split(separator: "\n")` returns
        // one giant line and parses nothing.
        let crlfFixture = Self.fixture.replacingOccurrences(of: "\n", with: "\r\n")
        let log = GuideLogParser.parse(crlfFixture)
        #expect(log.guideSessions.count == 1)
        #expect(log.guideSessions[0].entries.count == 4)
        #expect(log.calibrations.count == 1)
    }

    @Test func coalescerMergesConsecutiveRepeats() {
        let infos = [
            InfoEntry(frame: 1, text: "Server received PAUSE"),
            InfoEntry(frame: 2, text: "Server received PAUSE"),
            InfoEntry(frame: 3, text: "Server received PAUSE"),
            InfoEntry(frame: 4, text: "Settling started"),
        ]
        let out = InfoCoalescer.coalesce(infos)
        #expect(out.count == 2)
        #expect(out[0].text == "Server received PAUSE")
        #expect(out[0].repeats == 3)
        #expect(out[0].frame == 3)
        #expect(out[1].text == "Settling started")
    }

    @Test func coalescerReplacesParameterChangesSameFrame() {
        let infos = [
            InfoEntry(frame: 5, text: "MultiStar = false"),
            InfoEntry(frame: 5, text: "MultiStar = true"),
            InfoEntry(frame: 6, text: "MultiStar = false"),
        ]
        let out = InfoCoalescer.coalesce(infos)
        #expect(out.count == 2)
        #expect(out[0].text == "MultiStar = true")
        #expect(out[1].text == "MultiStar = false")
    }

    @Test func coalescerReplacesSetLockPosWithDither() {
        let infos = [
            InfoEntry(frame: 10, text: "SET LOCK POS 320, 240"),
            InfoEntry(frame: 10, text: "DITHER by 1.5, -2.0"),
        ]
        let out = InfoCoalescer.coalesce(infos)
        #expect(out.count == 1)
        #expect(out[0].text == "DITHER by 1.5, -2.0")
    }

    @Test func coalescerKeepsUnrelatedSameFrameInfos() {
        let infos = [
            InfoEntry(frame: 10, text: "Settling started"),
            InfoEntry(frame: 10, text: "DITHER by 1, 2"),
        ]
        let out = InfoCoalescer.coalesce(infos)
        #expect(out.count == 2)
    }

    @Test func infoKindsClassifyCorrectly() {
        #expect(InfoKind.classify("Settling started") == .settlingStarted)
        #expect(InfoKind.classify("Settling complete") == .settlingComplete)
        #expect(InfoKind.classify("Settling failed") == .settlingFailed)
        #expect(InfoKind.classify("DITHER by 1, 2") == .dither)
        #expect(InfoKind.classify("Star lost - low SNR") == .starLost)
        #expect(InfoKind.classify("Frame dropped") == .frameDropped)
        #expect(InfoKind.classify("SET LOCK POS 100, 200") == .setLockPos)
        #expect(InfoKind.classify("Server received PAUSE") == .serverEvent)
        #expect(InfoKind.classify("MultiStar = true") == .parameterChange)
        #expect(InfoKind.classify("Random text") == .other)
    }

    @Test func parsesBundledSampleLog() throws {
        let bundle = Bundle(for: FixtureAnchor.self)
        let url = try #require(
            bundle.url(forResource: "sample_short", withExtension: "txt", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "sample_short", withExtension: "txt"),
            "sample_short.txt fixture must be bundled with the test target"
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        let log = GuideLogParser.parse(text)
        #expect(!log.sections.isEmpty, "expected at least one parsed section in real log")
        #expect(log.phdVersion.contains("2.6"))
    }
}

private final class FixtureAnchor {}
