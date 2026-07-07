import Testing
import Foundation
@testable import Ephemeris

/// The parser tolerates malformed rows (never crashes, never fails the file),
/// but it must COUNT what it coerces — a corrupt log silently reading as
/// perfect zero-error guiding was audit finding 10.
@Suite("Parser malformed-field accounting")
struct ParserMalformedFieldTests {

    private let header = """
    PHD2 version 2.6.13, Log version 2.5
    Guiding Begins at 2026-07-01 22:00:00
    Frame,Time,mount,dx,dy,RARawDistance,DECRawDistance,RAGuideDistance,DECGuideDistance,RADuration,RADirection,DECDuration,DECDirection,XStep,YStep,StarMass,SNR,ErrorCode
    """

    @Test func healthyLogHasZeroMalformedCount() {
        let log = GuideLogParser.parse(header + """

        1,1.0,"Mount",0.1,0.2,0.15,0.25,0.1,0.2,20,W,10,S,,,1200,25.0,0
        2,2.0,"Mount",0.2,0.1,0.05,0.15,0.2,0.1,,,,,,,1210,26.0,0
        """)
        #expect(log.guideSessions.first?.malformedFieldCount == 0)
    }

    @Test func garbageNumericFieldsAreCountedNotSilent() {
        let log = GuideLogParser.parse(header + """

        1,1.0,"Mount",GARBAGE,0.2,###,0.25,0.1,0.2,20,W,10,S,,,1200,25.0,0
        2,2.0,"Mount",0.2,0.1,0.05,0.15,0.2,0.1,20,W,10,S,,,1210,26.0,0
        """)
        let session = log.guideSessions.first
        // dx and RARawDistance were unreadable: coerced to 0 AND counted.
        #expect(session?.malformedFieldCount == 2)
        #expect(session?.entries.count == 2)
        #expect(session?.entries.first?.dx == 0)
    }

    @Test func unparseableFrameOrTimeCountsAsMalformedRow() {
        let log = GuideLogParser.parse(header + """

        1,NOTATIME,"Mount",0.1,0.2,0.15,0.25,0.1,0.2,20,W,10,S,,,1200,25.0,0
        2,2.0,"Mount",0.2,0.1,0.05,0.15,0.2,0.1,20,W,10,S,,,1210,26.0,0
        """)
        let session = log.guideSessions.first
        #expect(session?.malformedFieldCount == 1)
        #expect(session?.entries.count == 1)
    }

    @Test func truncatedFinalLineIsNotCounted() {
        // PHD2 killed mid-write leaves a short last row — normal, not suspect.
        let log = GuideLogParser.parse(header + """

        1,1.0,"Mount",0.1,0.2,0.15,0.25,0.1,0.2,20,W,10,S,,,1200,25.0,0
        2,2.0,"Mount",0.2,0.1
        """)
        let session = log.guideSessions.first
        #expect(session?.malformedFieldCount == 0)
        #expect(session?.entries.count == 1)
    }

    @Test func emptyFieldsAreLegitimateZeroesNotSuspect() {
        let log = GuideLogParser.parse(header + """

        1,1.0,"Mount",0.1,0.2,0.15,0.25,0.1,0.2,,,,,,,1200,25.0,0
        """)
        #expect(log.guideSessions.first?.malformedFieldCount == 0)
    }

    @Test func mergedSessionsSumTheirCounts() {
        var a = GuideSession()
        a.startedAt = .init(timeIntervalSince1970: 1_000)
        a.malformedFieldCount = 3
        a.entries = [GuideEntry(frame: 1, time: 1, deviceKind: .mount, dx: 0, dy: 0,
                                raRawDistance: 0, decRawDistance: 0,
                                raGuideDistance: 0, decGuideDistance: 0,
                                raDuration: 0, decDuration: 0, xStep: nil, yStep: nil,
                                starMass: 1, snr: 1, errorCode: 0,
                                included: true, guiding: true, info: nil)]
        var b = a
        b.startedAt = .init(timeIntervalSince1970: 2_000)
        b.malformedFieldCount = 2
        let merged = GuideSessionMerger.merge([a, b])
        #expect(merged.malformedFieldCount == 5)
    }
}

extension ParserMalformedFieldTests {
    @Test func garbageAOStepFieldsAreCounted() {
        let log = GuideLogParser.parse(header + """

        1,1.0,"AO",0.1,0.2,0.15,0.25,0.1,0.2,20,W,10,S,BAD,7,1200,25.0,0
        """)
        let session = log.guideSessions.first
        // xStep "BAD" is present but unreadable: counted, and stays nil so the
        // duration fields keep their values. yStep 7 applies normally.
        #expect(session?.malformedFieldCount == 1)
        #expect(session?.entries.first?.xStep == nil)
        #expect(session?.entries.first?.yStep == 7)
    }
}
