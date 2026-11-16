//
//  NightRMSTests.swift
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
import SwiftData
import Testing
@testable import Ephemeris

/// The night RMS is the frame-weighted median of per-session RMS. It replaced
/// a frame-weighted quadrature mean after an ASIAir night with a few runaway
/// sessions (star dragged hundreds of pixels off the lock position) read 107″
/// when most of its guiding was under 1″.
struct NightRMSTests {

    private func s(_ rms: Double, _ frames: Int) -> NightRMS.Session {
        NightRMS.Session(rmsArcsec: rms, frames: frames)
    }

    @Test func emptyNightIsZero() {
        #expect(NightRMS.frameWeightedMedian([]) == 0)
        #expect(NightRMS.frameWeightedMedian([s(1.2, 0)]) == 0)
    }

    @Test func singleSessionIsItsOwnRMS() {
        #expect(NightRMS.frameWeightedMedian([s(0.73, 400)]) == 0.73)
    }

    @Test func shortRunawayDoesNotSwampTheNight() {
        // 800 frames of good guiding, 51 frames of a mount that stopped tracking.
        #expect(NightRMS.frameWeightedMedian([s(0.8, 800), s(1216.5, 51)]) == 0.8)
    }

    @Test func manyFailedStartsDoNotOutvoteOneLongSession() {
        // Six 5-frame failed attempts against one 600-frame session: a plain
        // median of sessions would pick a failed attempt; weighting by frames
        // picks the session where the guiding time was.
        let night = (0..<6).map { _ in s(90, 5) } + [s(0.9, 600)]
        #expect(NightRMS.frameWeightedMedian(night) == 0.9)
    }

    @Test func aMostlyBadNightStillReadsBad() {
        // The median describes where the guiding time went; it doesn't hide a
        // night whose longest sessions were bad.
        #expect(NightRMS.frameWeightedMedian([s(0.5, 10), s(2.0, 1000)]) == 2.0)
    }

    @Test func exactHalfAveragesTheStraddlingSessions() {
        #expect(NightRMS.frameWeightedMedian([s(1.0, 100), s(0.5, 100)]) == 0.75)
    }

    @Test func orderDoesNotMatter() {
        let night = [s(3.0, 20), s(0.6, 300), s(1.1, 250), s(0.4, 40)]
        #expect(NightRMS.frameWeightedMedian(night) == NightRMS.frameWeightedMedian(night.reversed()))
        #expect(NightRMS.frameWeightedMedian(night) == 0.6)
    }

    /// End to end: the ingestor stores the median, so a runaway session moves
    /// the worst-session figure but not the night RMS.
    @MainActor
    @Test func ingestorStoresTheMedianNotTheMean() async throws {
        let header = """
        Pixel scale = 2.00 arc-sec/px, Binning = 1, Focal length = 400 mm
        Equipment Profile = Test Rig
        Mount = Test Mount,  connected, guiding enabled, xAngle = 0.0, xRate = 1.000, yAngle = 90.0, yRate = 1.000, parity = +/+,
        Frame,Time,mount,dx,dy,RARawDistance,DECRawDistance,RAGuideDistance,DECGuideDistance,RADuration,RADirection,DECDuration,DECDirection,XStep,YStep,StarMass,SNR,ErrorCode
        """
        let good = (1...8).map { i in
            let v = i.isMultiple(of: 2) ? 0.2 : -0.2
            return "\(i),\(Double(i)),\"Mount\",0,0,\(v),\(-v),0,0,0,,0,,,,1000,30.00,0"
        }.joined(separator: "\n")
        let runaway = (1...3).map { i in
            "\(i),\(Double(i)),\"Mount\",0,0,\(Double(i) * 100),0,0,0,0,,0,,,,1000,30.00,0"
        }.joined(separator: "\n")
        let text = """
        PHD2 version 2.6.13, Log version 2.5. Log enabled at 2026-11-01 20:00:00

        Guiding Begins at 2026-11-01 20:00:00
        \(header)
        \(good)
        Guiding Ends at 2026-11-01 20:00:10

        Guiding Begins at 2026-11-01 20:01:00
        \(header)
        \(runaway)
        Guiding Ends at 2026-11-01 20:01:05
        """
        let log = GuideLogParser.parse(text)
        #expect(log.guideSessions.count == 2)

        let goodRMS = SessionStatsCalculator.calculate(log.guideSessions[0], manualExclusionRanges: []).rmsTotal * 2.0
        let runawayRMS = SessionStatsCalculator.calculate(log.guideSessions[1], manualExclusionRanges: []).rmsTotal * 2.0

        let library = try EphemerisLibrary(inMemory: true)
        let ingestor = LibraryIngestor(modelContainer: library.container)
        let result = try await ingestor.ingest(log: log, sourceBytes: Data(text.utf8),
                                               sourceFilePath: "/tmp/night-rms.txt",
                                               rigProfile: RigProfile(currentName: "Test Rig"))
        let id = result.nightRecordId
        let night = try #require(try library.container.mainContext.fetch(
            FetchDescriptor<NightRecordEntity>(predicate: #Predicate { $0.id == id })).first)

        #expect(abs(night.medianRMSArcsec - goodRMS) < 1e-9)
        #expect(abs(night.worstSessionRMSArcsec - runawayRMS) < 1e-9)
        #expect(runawayRMS > 100 * goodRMS)
    }
}
