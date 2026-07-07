import Testing
import Foundation
@testable import Ephemeris

/// Tests for the chart decimation model. The contract that matters: extremes
/// always survive decimation, gap sentinels stay as line breaks, budgets hold,
/// and the binary-search hover lookup agrees with a linear scan.
@Suite("Guide chart decimation")
struct GuideChartDataTests {

    private func makeEntry(frame: Int, time: Double,
                           ra: Double = 0, dec: Double = 0,
                           raDuration: Int = 0, decDuration: Int = 0,
                           included: Bool = true) -> GuideEntry {
        GuideEntry(frame: frame, time: time, deviceKind: .mount,
                   dx: ra, dy: dec,
                   raRawDistance: ra, decRawDistance: dec,
                   raGuideDistance: 0, decGuideDistance: 0,
                   raDuration: raDuration, decDuration: decDuration,
                   xStep: nil, yStep: nil,
                   starMass: 100, snr: 20, errorCode: 0,
                   included: included, guiding: true, info: nil)
    }

    private func makeSession(entries: [GuideEntry]) -> GuideSession {
        var session = GuideSession()
        session.entries = entries
        return session
    }

    private func key(for session: GuideSession,
                     lo: Double? = nil, hi: Double? = nil) -> GuideChartData.Key {
        GuideChartData.Key(sessionID: session.id, axisMode: .raDec,
                           domainLo: lo, domainHi: hi)
    }

    @Test func smallSessionsPassThroughUndecimated() {
        let entries = (0..<500).map { makeEntry(frame: $0, time: Double($0), ra: sin(Double($0))) }
        let session = makeSession(entries: entries)
        let data = GuideChartData(session: session, key: key(for: session))
        #expect(data.raPoints.count == 500)
    }

    @Test func largeSessionsStayUnderBudget() {
        let entries = (0..<100_000).map { makeEntry(frame: $0, time: Double($0) * 0.5, ra: sin(Double($0) * 0.01)) }
        let session = makeSession(entries: entries)
        let data = GuideChartData(session: session, key: key(for: session))
        #expect(data.raPoints.count <= GuideChartData.defaultBucketCount * 4)
        #expect(data.raPoints.count > GuideChartData.defaultBucketCount / 2)
    }

    @Test func spikeSurvivesDecimation() {
        var entries = (0..<50_000).map { makeEntry(frame: $0, time: Double($0), ra: 0.1) }
        entries[31_337] = makeEntry(frame: 31_337, time: 31_337, ra: 9.75)
        let session = makeSession(entries: entries)
        let data = GuideChartData(session: session, key: key(for: session))
        #expect(data.raPoints.contains { $0.valuePx == 9.75 })
        #expect(abs(data.maxSeriesMagnitudePx - 9.75) < 1e-9)
    }

    @Test func gapSentinelsSurviveAsLineBreaks() {
        var entries = (0..<50_000).map { makeEntry(frame: $0, time: Double($0), ra: 0.2) }
        entries[25_000] = makeEntry(frame: 25_000, time: 25_000, ra: .nan, included: false)
        let session = makeSession(entries: entries)
        let data = GuideChartData(session: session, key: key(for: session))
        #expect(data.raPoints.contains { $0.valuePx.isNaN })
    }

    @Test func worstCorrectionSurvives() {
        var entries = (0..<50_000).map {
            makeEntry(frame: $0, time: Double($0), ra: 0.1, raDuration: 20)
        }
        entries[40_000] = makeEntry(frame: 40_000, time: 40_000, ra: 0.1, raDuration: 1500)
        let session = makeSession(entries: entries)
        let data = GuideChartData(session: session, key: key(for: session))
        // xRate defaults to 1.0 px/s, so 1500 ms = 1.5 px.
        #expect(data.raCorrections.contains { abs($0.valuePx - 1.5) < 1e-9 })
        #expect(data.raCorrections.count <= GuideChartData.defaultBucketCount + 4)
    }

    @Test func zoomedDomainIncludesEdgeNeighbors() {
        let entries = (0..<10_000).map { makeEntry(frame: $0, time: Double($0), ra: 0.3) }
        let session = makeSession(entries: entries)
        let data = GuideChartData(session: session, key: key(for: session, lo: 4000, hi: 4100))
        let times = data.raPoints.map(\.time)
        // One point beyond each edge so the line enters and exits the plot.
        #expect(times.contains { $0 < 4000 })
        #expect(times.contains { $0 > 4100 })
    }

    @Test func excludedEntriesDoNotDriveYDomain() {
        var entries = (0..<1000).map { makeEntry(frame: $0, time: Double($0), ra: 0.2) }
        entries[500] = makeEntry(frame: 500, time: 500, ra: 50.0, included: false)
        let session = makeSession(entries: entries)
        let data = GuideChartData(session: session, key: key(for: session))
        #expect(abs(data.maxSeriesMagnitudePx - 0.2) < 1e-9)
    }

    @Test func nearestEntryMatchesLinearScan() {
        var entries = (0..<10_000).map { makeEntry(frame: $0, time: Double($0) * 1.7, ra: 0.1) }
        entries[5000] = makeEntry(frame: 5000, time: 5000 * 1.7, ra: .nan, included: false)
        let session = makeSession(entries: entries)
        let data = GuideChartData(session: session, key: key(for: session))

        for t in [0.0, 3.0, 8499.9, 8500.5, 16_998.0, 99_999.0] {
            let expected = session.entries.lazy
                .filter { !$0.raRawDistance.isNaN }
                .min { abs($0.time - t) < abs($1.time - t) }
            let got = data.nearestRealEntry(to: t)
            #expect(got?.frame == expected?.frame, "mismatch at t=\(t)")
        }
    }

    @Test func settlingBandsPairStartWithEnd() {
        var session = makeSession(entries: (0..<100).map { makeEntry(frame: $0, time: Double($0)) })
        session.infos = [
            InfoEntry(frame: 10, text: "Settling started"),
            InfoEntry(frame: 20, text: "Settling complete"),
            InfoEntry(frame: 50, text: "DITHER by 2.0"),
        ]
        let data = GuideChartData(session: session, key: key(for: session))
        #expect(data.settlingBands.count == 1)
        #expect(data.settlingBands.first?.succeeded == true)
        #expect(data.eventMarkers.contains { $0.kind == .dither })
    }
}
