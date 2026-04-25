//
//  MergerTests.swift
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

struct MergerTests {

    @Test func mergeOfSingleSessionReturnsSelf() {
        let s = makeSession(start: Date(timeIntervalSince1970: 1_700_000_000), times: [0, 5, 10])
        let merged = GuideSessionMerger.merge([s])
        #expect(merged.entries.map(\.time) == [0, 5, 10])
    }

    @Test func mergeRebasesFollowingSessionsToFirstStart() {
        // Session A: starts at T=0, frames at 0, 5, 10
        // Session B: starts at T=600 (10 min later), frames at 0, 5, 10
        // Merged should start at the earliest startedAt and shift B by +600.
        // A NaN-valued boundary sentinel is inserted between the two sessions
        // so Swift Charts breaks the line at the wall-clock gap.
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = makeSession(start: t0, times: [0, 5, 10])
        let b = makeSession(start: t0.addingTimeInterval(600), times: [0, 5, 10])
        let merged = GuideSessionMerger.merge([a, b])
        #expect(merged.entries.count == 7)              // 3 + sentinel + 3
        let included = merged.entries.filter(\.included)
        #expect(included.map(\.time) == [0, 5, 10, 600, 605, 610])
        #expect(merged.startedAt == t0)
    }

    @Test func mergeReassignsFrameNumbers() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = makeSession(start: t0, times: [0, 5])             // frames 1, 2
        let b = makeSession(start: t0.addingTimeInterval(60), times: [0, 5])  // frames 1, 2 → become 4, 5 (sentinel = 3)
        let merged = GuideSessionMerger.merge([a, b])
        let included = merged.entries.filter(\.included)
        #expect(included.map(\.frame) == [1, 2, 4, 5])
    }

    @Test func mergeSortsByStartDateRegardlessOfInputOrder() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let early = makeSession(start: t0, times: [0])
        let late = makeSession(start: t0.addingTimeInterval(120), times: [0])
        let merged = GuideSessionMerger.merge([late, early])
        let included = merged.entries.filter(\.included)
        #expect(included.map(\.time) == [0, 120])
    }

    @Test func mergeFallsBackToSequencingWhenDatesMissing() {
        var a = GuideSession()
        a.entries = [makeEntry(frame: 1, time: 0), makeEntry(frame: 2, time: 5)]
        var b = GuideSession()
        b.entries = [makeEntry(frame: 1, time: 0), makeEntry(frame: 2, time: 5)]
        let merged = GuideSessionMerger.merge([a, b])
        // Session A 0..5, sentinel, then session B starts at offset = last + 1.
        let included = merged.entries.filter(\.included)
        #expect(included.map(\.time) == [0, 5, 6, 11])
    }

    // MARK: - Boundary sentinels

    @Test func mergeInsertsBoundarySentinelBetweenSessions() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = makeSession(start: t0, times: [0, 5, 10])
        let b = makeSession(start: t0.addingTimeInterval(600), times: [0, 5, 10])
        let merged = GuideSessionMerger.merge([a, b])
        let sentinels = merged.entries.filter { !$0.included }
        #expect(sentinels.count == 1)
        let s = sentinels.first!
        #expect(s.raRawDistance.isNaN)
        #expect(s.decRawDistance.isNaN)
        #expect(s.dx.isNaN)
        #expect(s.dy.isNaN)
        // Sentinel time sits between the previous session's last frame and the
        // following session's first frame.
        #expect(s.time > 10 && s.time < 600)
    }

    @Test func mergeOfThreeSessionsInsertsTwoSentinels() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let a = makeSession(start: t0, times: [0, 5])
        let b = makeSession(start: t0.addingTimeInterval(100), times: [0, 5])
        let c = makeSession(start: t0.addingTimeInterval(200), times: [0, 5])
        let merged = GuideSessionMerger.merge([a, b, c])
        #expect(merged.entries.filter { !$0.included }.count == 2)
        #expect(merged.entries.filter(\.included).count == 6)
    }

    @Test func mergeOfSingleSessionInsertsNoSentinel() {
        let s = makeSession(start: Date(timeIntervalSince1970: 1_700_000_000), times: [0, 5, 10])
        let merged = GuideSessionMerger.merge([s])
        #expect(merged.entries.filter { !$0.included }.isEmpty)
    }

    // MARK: - Helpers

    private func makeSession(start: Date, times: [Double]) -> GuideSession {
        var s = GuideSession()
        s.startedAt = start
        s.pixelScale = 1.0
        s.entries = times.enumerated().map { i, t in
            makeEntry(frame: i + 1, time: t)
        }
        return s
    }

    private func makeEntry(frame: Int, time: Double) -> GuideEntry {
        GuideEntry(
            frame: frame, time: time, deviceKind: .mount,
            dx: 0, dy: 0,
            raRawDistance: 0, decRawDistance: 0,
            raGuideDistance: 0, decGuideDistance: 0,
            raDuration: 0, decDuration: 0,
            xStep: nil, yStep: nil,
            starMass: 0, snr: 0, errorCode: 0,
            included: true, guiding: true, info: nil
        )
    }
}
