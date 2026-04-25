//
//  CSVExporterTests.swift
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

struct CSVExporterTests {

    @Test func sessionStatsHasHeaderAndOneRow() {
        let session = makeSession(raValues: [0.5, -0.5, 0.5, -0.5])
        let csv = CSVExporter.sessionStatsCSV(session)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        #expect(lines[0].contains("RMS_RA_px"))
        #expect(lines[0].contains("RMS_RA_arcsec"))
        // Row should have the same comma count as header — `components(separatedBy:)`
        // preserves empty fields (e.g. blank Started date) that `split` would drop.
        let headerCols = String(lines[0]).components(separatedBy: ",").count
        let rowCols = String(lines[1]).components(separatedBy: ",").count
        #expect(headerCols == rowCols)
    }

    @Test func sessionStatsRespectsManualExclusion() {
        let session = makeSession(raValues: [0.0, 5.0, 0.0, 0.0, 0.0])
        // Without exclusion, the spike inflates RMS.
        let unfiltered = CSVExporter.sessionStatsCSV(session)
        // Excluding only the spike's frame index should drop RMS noticeably.
        // Frame 2 is at time = 2.0; exclude time 1.5...2.5.
        let filtered = CSVExporter.sessionStatsCSV(session, manualExclusionRanges: [1.5...2.5])
        // Sanity: outputs differ.
        #expect(unfiltered != filtered)
    }

    @Test func frameDataHasOneRowPerEntry() {
        let session = makeSession(raValues: [1, 2, 3])
        let csv = CSVExporter.frameDataCSV(session)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        // header + 3 data rows
        #expect(lines.count == 4)
        #expect(lines[0].contains("RA_RawDist"))
    }

    @Test func aggregateHasOneRowPerSession() {
        var log = GuideLog()
        log.guideSessions = [
            makeSession(raValues: [0.1, -0.1]),
            makeSession(raValues: [0.5, -0.5, 0.5]),
        ]
        let csv = CSVExporter.aggregateCSV(log)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 3)   // header + 2 sessions
        #expect(lines[0].contains("Pixel_scale_arcsec_per_px"))
    }

    @Test func quotesInfoFieldsContainingCommas() {
        var session = makeSession(raValues: [0])
        session.entries[0].info = "DITHER by 1.5, -2.0"
        let csv = CSVExporter.frameDataCSV(session)
        // Embedded comma must be wrapped in quotes per RFC 4180.
        #expect(csv.contains("\"DITHER by 1.5, -2.0\""))
    }

    // MARK: - Helpers

    private func makeSession(raValues: [Double]) -> GuideSession {
        var s = GuideSession()
        s.pixelScale = 1.0
        s.entries = raValues.enumerated().map { i, v in
            GuideEntry(
                frame: i + 1, time: Double(i + 1), deviceKind: .mount,
                dx: 0, dy: 0,
                raRawDistance: v, decRawDistance: 0,
                raGuideDistance: 0, decGuideDistance: 0,
                raDuration: 0, decDuration: 0,
                xStep: nil, yStep: nil,
                starMass: 0, snr: 0, errorCode: 0,
                included: true, guiding: true, info: nil
            )
        }
        return s
    }
}
