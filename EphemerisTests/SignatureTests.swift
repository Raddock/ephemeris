//
//  SignatureTests.swift
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

struct SignatureTests {

    // MARK: - PHD2LogSignature.classify

    @Test func realPHD2LogIsConfirmed() throws {
        let bundle = Bundle(for: SignatureFixtureAnchor.self)
        let url = try #require(
            bundle.url(forResource: "sample_short", withExtension: "txt", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "sample_short", withExtension: "txt")
        )
        let data = try Data(contentsOf: url)
        #expect(PHD2LogSignature.classify(data) == .confirmed)
    }

    @Test func arbitraryTextIsRejected() {
        let text = """
        Shopping list
        - milk
        - bread
        - cheese
        """
        let data = Data(text.utf8)
        #expect(PHD2LogSignature.classify(data) == .notPHD2)
    }

    @Test func sourceCodeIsRejected() {
        let text = """
        import Foundation

        func main() {
            print("hello")
        }
        """
        let data = Data(text.utf8)
        #expect(PHD2LogSignature.classify(data) == .notPHD2)
    }

    @Test func binaryBlobIsDetected() {
        // PNG header bytes contain 0x00 in the IHDR chunk size field; any
        // input with NUL bytes is treated as binary.
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52]
        #expect(PHD2LogSignature.classify(Data(png)) == .binary)
    }

    @Test func emptyDataIsRejected() {
        #expect(PHD2LogSignature.classify(Data()) == .notPHD2)
    }

    @Test func phd2FragmentWithoutBannerIsLikely() {
        // Real-world: a log with the version line stripped or split. Should
        // still be recognized via the section delimiters.
        let text = """
        Equipment Profile = Edge-10m

        Guiding Begins at 2026-04-21 21:31:36
        Pixel scale = 0.62 arc-sec/px
        Frame,Time,mount,dx,dy,RARawDistance,DECRawDistance,RAGuideDistance,DECGuideDistance,RADuration,RADirection,DECDuration,DECDirection,XStep,YStep,StarMass,SNR,ErrorCode
        1,7.481,"Mount",-0.156,0.683,-0.246,-0.589,0.000,-0.118,0,,7,N,,,1288508,532.50,0
        """
        let data = Data(text.utf8)
        #expect(PHD2LogSignature.classify(data) == .likely)
    }

    @Test func calibrationOnlyFileIsLikely() {
        let text = """
        Calibration Begins at 2026-04-21 21:00:00
        Direction,Step,dx,dy,x,y,Dist
        West,1,0.0,0.0,100.0,100.0,0.0
        """
        let data = Data(text.utf8)
        #expect(PHD2LogSignature.classify(data) == .likely)
    }

    @Test func windowsCRLFLogIsConfirmed() {
        // PHD2 on Windows uses CRLF; signature must work regardless.
        let text = "PHD2 version 2.6.14 [Windows], Log version 2.5.\r\nINFO: started\r\n"
        let data = Data(text.utf8)
        #expect(PHD2LogSignature.classify(data) == .confirmed)
    }

    // MARK: - GuideLogParser empty-input contract

    @Test func parseEmptyStringReturnsEmptyLog() {
        let log = GuideLogParser.parse("")
        #expect(log.isEmpty)
        #expect(log.guideSessions.isEmpty)
        #expect(log.calibrations.isEmpty)
        #expect(log.sections.isEmpty)
    }

    @Test func parseTextWithNoRecognizedSectionsReturnsEmptyLog() {
        let log = GuideLogParser.parse("just some random text\nwith no PHD2 markers\n")
        #expect(log.isEmpty)
    }
}

/// Bundle anchor — used to locate the test target's bundle so we can find the
/// sample log fixture at runtime.
private final class SignatureFixtureAnchor {}
