import XCTest
import SwiftData
@testable import Ephemeris

/// Tests for the Phase 3 LibraryIngestor. Uses an in-memory ModelContainer
/// so tests don't touch the user's real Library.store.
@MainActor
final class LibraryIngestorTests: XCTestCase {

    private var library: EphemerisLibrary!
    private var ingestor: LibraryIngestor!

    override func setUp() async throws {
        try await super.setUp()
        library = try EphemerisLibrary(inMemory: true)
        ingestor = LibraryIngestor(modelContainer: library.container)
    }

    override func tearDown() async throws {
        library = nil
        ingestor = nil
        try await super.tearDown()
    }

    func test_ingest_persistsNightRecord() async throws {
        let log = makeMinimalLog()
        let bytes = Data("PHD2 version 2.6.14\n".utf8)
        var profile = RigProfile(currentName: "Edge-10m")
        profile.imagingFocalLength = 1960
        profile.imagingPixelSize = 5.9

        let result = try await ingestor.ingest(log: log,
                                               sourceBytes: bytes,
                                               sourceFilePath: "/tmp/test.txt",
                                               rigProfile: profile)
        XCTAssertTrue(result.didCreate)
        XCTAssertGreaterThan(result.observationCount, 0)
    }

    func test_ingest_idempotent_onContentHash() async throws {
        let log = makeMinimalLog()
        let bytes = Data("identical bytes".utf8)
        var profile = RigProfile(currentName: "Edge-10m")
        profile.imagingFocalLength = 1960
        profile.imagingPixelSize = 5.9

        let first = try await ingestor.ingest(log: log, sourceBytes: bytes,
                                              sourceFilePath: "/tmp/a.txt",
                                              rigProfile: profile)
        let second = try await ingestor.ingest(log: log, sourceBytes: bytes,
                                               sourceFilePath: "/tmp/b.txt",
                                               rigProfile: profile)
        XCTAssertTrue(first.didCreate)
        XCTAssertFalse(second.didCreate)
        XCTAssertEqual(first.nightRecordId, second.nightRecordId)
    }

    private func makeMinimalLog() -> GuideLog {
        let now = Date()
        let calDate = now.addingTimeInterval(-40 * 86400)  // 40 days ago — triggers staleness alert
        var details = CalibrationDetails()
        details.legCompletions[.west] = LegCompletion(angleDeg: 0, ratePxPerSec: 0.1)
        details.legCompletions[.north] = LegCompletion(angleDeg: 77.8, ratePxPerSec: 0.1)  // 12.2° ortho
        let cal = Calibration(startedAt: calDate, device: .mount,
                              rawHeader: [], entries: [], details: details)
        let session = GuideSession(
            startedAt: now,
            rawHeader: ["Equipment Profile = Edge-10m"],
            mount: GuideDevice(kind: .mount),
            ao: nil, pixelScale: 0.62, declination: 0,
            entries: [], infos: []
        )
        return GuideLog(phdVersion: "2.6.14", logVersion: "2.5",
                        sections: [.calibration(0), .guide(0)],
                        guideSessions: [session],
                        calibrations: [cal])
    }
}
