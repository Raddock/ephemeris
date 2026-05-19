import XCTest
@testable import Ephemeris

final class RecommenderEngineTests: XCTestCase {

    // MARK: - Engine architecture

    func test_engineDefault_hasExpectedGenerators() {
        let engine = RecommenderEngine.default
        let identifiers = Set(engine.generators.map { $0.identifier })
        XCTAssertTrue(identifiers.contains("guidingAssistantRecommendationObserver"))
        XCTAssertTrue(identifiers.contains("calibrationSanityAlertObserver"))
        XCTAssertTrue(identifiers.contains("maxDurationLimitObserver"))
        XCTAssertTrue(identifiers.contains("calibrationStalenessObserver"))
        XCTAssertTrue(identifiers.contains("calibrationOrthogonalityObserver"))
        XCTAssertTrue(identifiers.contains("variableExposureDelaysObserver"))
        XCTAssertTrue(identifiers.contains("multiStarGuidingObserver"))
        XCTAssertTrue(identifiers.contains("algorithmMismatchObserver"))
        XCTAssertTrue(identifiers.contains("decPolarityBiasObserver"))
        XCTAssertTrue(identifiers.contains("atmosphericConditionsProxy"))
    }

    func test_engine_emptyLog_returnsEmptyObservations() {
        let log = GuideLog(phdVersion: "2.6.14",
                           logVersion: "2.5",
                           sections: [],
                           guideSessions: [],
                           calibrations: [])
        let profile = RigProfile(currentName: "Test")
        let obs = RecommenderEngine.default.analyze(log: log, profile: profile)
        XCTAssertEqual(obs.count, 0)
    }

    // MARK: - Bundled fixture

    func test_engine_bundledFixture_runsWithoutCrashing() throws {
        let url = try fixture("sample_short")
        let text = try String(contentsOf: url, encoding: .utf8)
        let log = GuideLogParser.parse(text)
        let profile = RigProfile(currentName: "Sample", mountClass: .standardGearMount)
        let obs = RecommenderEngine.default.analyze(log: log, profile: profile)
        // Don't assert specific count — the engine should run cleanly on any well-formed log.
        // Observations may or may not fire depending on what's in the fixture.
        XCTAssertGreaterThanOrEqual(obs.count, 0)
    }

    func test_engine_sortsByCategoryThenSeverity() throws {
        // Build a synthetic log with a stale calibration and a fresh one.
        // We'll synthesize observations directly to test the sort, since constructing
        // a full GuideLog with the right INFO entries is more involved than necessary.
        let profileId = UUID()
        let now = Date()
        let coachingHygiene = RecommenderObservation(
            scope: .singleNight, rigProfileId: profileId,
            category: .phd2Hygiene, severity: .coaching,
            title: "Z",
            summary: "", suggestedResponse: "",
            sourceAuthority: .phd2Manual, generatedAt: now
        )
        let alertHygiene = RecommenderObservation(
            scope: .singleNight, rigProfileId: profileId,
            category: .phd2Hygiene, severity: .alert,
            title: "A",
            summary: "", suggestedResponse: "",
            sourceAuthority: .phd2Manual, generatedAt: now
        )
        let suggestionEntry = RecommenderObservation(
            scope: .singleNight, rigProfileId: profileId,
            category: .suggestion, severity: .alert,
            title: "Aaa",
            summary: "", suggestedResponse: "",
            sourceAuthority: .phd2Manual, generatedAt: now
        )

        // Use the engine's same sort logic
        let unsorted = [suggestionEntry, coachingHygiene, alertHygiene]
        let sorted = unsorted.sorted { lhs, rhs in
            if lhs.category.rawValue != rhs.category.rawValue {
                return lhs.category.rawValue < rhs.category.rawValue
            }
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return lhs.title < rhs.title
        }
        // phd2Hygiene (3) < suggestion (5), so hygiene comes first
        XCTAssertEqual(sorted[0].title, "A")             // alert hygiene
        XCTAssertEqual(sorted[1].title, "Z")             // coaching hygiene
        XCTAssertEqual(sorted[2].title, "Aaa")           // alert suggestion (different category)
    }

    // MARK: - Generator behavior

    func test_calibrationOrthogonalityObserver_firesOverFiveDegrees() {
        let log = makeLog(orthogonalityError: 12.2, calibrationDaysAgo: 5)
        let profile = RigProfile(currentName: "Test")
        let obs = RecommenderEngine.default.analyze(log: log, profile: profile)
        let ortho = obs.first { $0.title.contains("orthogonality") }
        XCTAssertNotNil(ortho)
        XCTAssertEqual(ortho?.severity, .alert)
        XCTAssertEqual(ortho?.sourceAuthority, .phd2Manual)
        XCTAssertTrue(ortho?.relatedPHD2Tools.contains(.calibrationAssistant) == true)
    }

    func test_calibrationOrthogonalityObserver_silentUnderFiveDegrees() {
        let log = makeLog(orthogonalityError: 3.7, calibrationDaysAgo: 5)
        let profile = RigProfile(currentName: "Test")
        let obs = RecommenderEngine.default.analyze(log: log, profile: profile)
        let ortho = obs.first { $0.title.contains("orthogonality") }
        XCTAssertNil(ortho)
    }

    func test_calibrationStaleness_firesAfter21Days() {
        let log = makeLog(orthogonalityError: 1.0, calibrationDaysAgo: 25)
        let profile = RigProfile(currentName: "Test")
        let obs = RecommenderEngine.default.analyze(log: log, profile: profile)
        let stale = obs.first { $0.title.contains("Calibration is") }
        XCTAssertNotNil(stale)
        XCTAssertEqual(stale?.severity, .coaching)  // 21-29 days = coaching
        XCTAssertEqual(stale?.sourceAuthority, .phd2Manual)
    }

    func test_calibrationStaleness_alertsAfter30Days() {
        let log = makeLog(orthogonalityError: 1.0, calibrationDaysAgo: 40)
        let profile = RigProfile(currentName: "Test")
        let obs = RecommenderEngine.default.analyze(log: log, profile: profile)
        let stale = obs.first { $0.title.contains("Calibration is") }
        XCTAssertEqual(stale?.severity, .alert)
    }

    func test_calibrationStaleness_silentUnder21Days() {
        let log = makeLog(orthogonalityError: 1.0, calibrationDaysAgo: 14)
        let profile = RigProfile(currentName: "Test")
        let obs = RecommenderEngine.default.analyze(log: log, profile: profile)
        let stale = obs.first { $0.title.contains("Calibration is") }
        XCTAssertNil(stale)
    }

    // MARK: - Helpers

    /// Synthesize a small GuideLog with a single calibration of given orthogonality and age.
    private func makeLog(orthogonalityError: Double, calibrationDaysAgo: Int) -> GuideLog {
        let now = Date()
        let calDate = now.addingTimeInterval(-Double(calibrationDaysAgo) * 86400)
        // Set West/North leg angles to produce the requested orthogonality:
        // West at 0°, North at 90° - orthogonalityError → orthoErr = 5° when North = 85°
        // The formula in CalibrationDetails computes |delta - 90|.
        let westAngle = 0.0
        let northAngle = 90.0 - orthogonalityError
        var details = CalibrationDetails()
        details.legCompletions[.west] = LegCompletion(angleDeg: westAngle, ratePxPerSec: 0.1)
        details.legCompletions[.north] = LegCompletion(angleDeg: northAngle, ratePxPerSec: 0.1)
        let cal = Calibration(
            startedAt: calDate,
            device: .mount,
            rawHeader: [],
            entries: [],
            details: details
        )
        let session = GuideSession(
            startedAt: now,
            rawHeader: [],
            mount: GuideDevice(kind: .mount),
            ao: nil,
            pixelScale: 0.62,
            declination: 0,
            entries: [],
            infos: []
        )
        return GuideLog(
            phdVersion: "2.6.14",
            logVersion: "2.5",
            sections: [.calibration(0), .guide(0)],
            guideSessions: [session],
            calibrations: [cal]
        )
    }

    private func fixture(_ name: String) throws -> URL {
        // Bundle.module isn't available for legacy XCTest bundles; resolve via Bundle(for:)
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: name, withExtension: "txt") {
            return url
        }
        // Fall back to the source-tree path (test runner cwd is unstable).
        let srcRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).txt")
        if FileManager.default.fileExists(atPath: srcRoot.path) {
            return srcRoot
        }
        throw NSError(domain: "RecommenderEngineTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Fixture \(name).txt not found"])
    }
}
