import XCTest
@testable import Ephemeris

final class CrossNightEngineTests: XCTestCase {

    private func profile() -> RigProfile {
        var p = RigProfile(currentName: "Edge-10m")
        p.imagingFocalLength = 1960
        p.imagingPixelSize = 5.9
        p.mountClass = .encoderBasedPremium
        p.hasHighPrecisionEncoders = true
        return p
    }

    private func nights(orthos: [Double?], hasGA: Bool = false, daysApart: Int = 1) -> [NightSummary] {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        return orthos.enumerated().map { idx, ortho in
            NightSummary(
                nightDate: start.addingTimeInterval(Double(idx * daysApart) * 86400),
                sessionsCount: 5,
                totalIntegrationMinutes: 60,
                medianRMSArcsec: 0.5,
                bestSessionRMSArcsec: 0.3,
                worstSessionRMSArcsec: 0.9,
                calibrationOrthogonalityDeg: ortho,
                guidingAssistantRan: hasGA && idx == orthos.count - 1
            )
        }
    }

    // MARK: - CalibrationAngleShiftObserver

    func test_calibrationAngleShift_firesOnTenDegreeStep() {
        let ctx = CrossNightContext(
            profile: profile(),
            nights: nights(orthos: [2.0, 2.0, 12.5]),  // 10.5° shift → alert tier
            annotations: []
        )
        let obs = CrossNightEngine.default.analyze(context: ctx)
        let shift = obs.first { $0.title.contains("orthogonality shifted") }
        XCTAssertNotNil(shift)
        XCTAssertEqual(shift?.severity, .alert)
        XCTAssertEqual(shift?.sourceAuthority, .ephemerisHeuristic)
        XCTAssertTrue(shift?.relatedPHD2Tools.contains(.calibrationAssistant) == true)
    }

    func test_calibrationAngleShift_patternTierAtSixDegrees() {
        let ctx = CrossNightContext(
            profile: profile(),
            nights: nights(orthos: [2.0, 8.0]),  // 6° shift → pattern tier
            annotations: []
        )
        let obs = CrossNightEngine.default.analyze(context: ctx)
        let shift = obs.first { $0.title.contains("orthogonality shifted") }
        XCTAssertEqual(shift?.severity, .pattern)
    }

    func test_calibrationAngleShift_silentBelowFiveDegrees() {
        let ctx = CrossNightContext(
            profile: profile(),
            nights: nights(orthos: [2.0, 6.0]),  // 4° shift → silent
            annotations: []
        )
        let obs = CrossNightEngine.default.analyze(context: ctx)
        XCTAssertNil(obs.first { $0.title.contains("orthogonality shifted") })
    }

    func test_calibrationAngleShift_suppressedByCalibrationAnnotation() {
        // The annotation is on the boundary date (the day of the 2nd calibration).
        let dates = [Date(timeIntervalSince1970: 1_750_000_000),
                     Date(timeIntervalSince1970: 1_750_086_400)]
        let nights = [
            NightSummary(nightDate: dates[0], calibrationOrthogonalityDeg: 2.0),
            NightSummary(nightDate: dates[1], calibrationOrthogonalityDeg: 12.0),
        ]
        let annotation = Annotation(
            rigProfileId: profile().id,
            eventDate: dates[1],
            categories: [.calibration],
            label: "Recalibrated post-OAG-fix"
        )
        let ctx = CrossNightContext(profile: profile(), nights: nights, annotations: [annotation])
        let obs = CrossNightEngine.default.analyze(context: ctx)
        XCTAssertNil(obs.first { $0.title.contains("orthogonality shifted") },
                     "Calibration annotation should suppress angle-shift observation")
    }

    // MARK: - GAFreshnessObserver

    func test_gaFreshness_firesWhenGANeverRun() {
        // GA-never-run only fires if the corpus spans >= 30 days. Span the nights wider.
        let ctx = CrossNightContext(profile: profile(),
                                    nights: nights(orthos: [2.0, 2.0, 2.0], hasGA: false, daysApart: 20),
                                    annotations: [])
        let obs = CrossNightEngine.default.analyze(context: ctx)
        XCTAssertNotNil(obs.first { $0.title.contains("never been run") })
    }

    func test_gaFreshness_alertAfter90Days() {
        let n = nights(orthos: [2.0, 2.0], hasGA: false, daysApart: 100)
        let ctx = CrossNightContext(profile: profile(), nights: n, annotations: [])
        let obs = CrossNightEngine.default.analyze(context: ctx)
        let ga = obs.first { $0.title.contains("Guiding Assistant") }
        XCTAssertNotNil(ga)
    }

    // MARK: - BaselineRegressionObserver

    func test_baselineRegression_firesWhenRecentExceedsP90() {
        // 10 historical nights at 0.4″, then 3 nights at 1.5″ → regression
        var rolls: [NightSummary] = []
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        for i in 0..<10 {
            rolls.append(NightSummary(
                nightDate: start.addingTimeInterval(Double(i) * 86400),
                medianRMSArcsec: 0.4
            ))
        }
        for i in 10..<13 {
            rolls.append(NightSummary(
                nightDate: start.addingTimeInterval(Double(i) * 86400),
                medianRMSArcsec: 1.5
            ))
        }
        let ctx = CrossNightContext(profile: profile(), nights: rolls, annotations: [])
        let obs = CrossNightEngine.default.analyze(context: ctx)
        XCTAssertNotNil(obs.first { $0.title.contains("Recent RMS above rig baseline") })
    }

    func test_baselineRegression_silentBelowFloor() {
        var rolls: [NightSummary] = []
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        for i in 0..<12 {
            rolls.append(NightSummary(
                nightDate: start.addingTimeInterval(Double(i) * 86400),
                medianRMSArcsec: 0.4
            ))
        }
        let ctx = CrossNightContext(profile: profile(), nights: rolls, annotations: [])
        let obs = CrossNightEngine.default.analyze(context: ctx)
        XCTAssertNil(obs.first { $0.title.contains("Recent RMS above rig baseline") })
    }

    func test_baselineRegression_needsAtLeastTenNights() {
        var rolls: [NightSummary] = []
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        for i in 0..<5 {
            rolls.append(NightSummary(
                nightDate: start.addingTimeInterval(Double(i) * 86400),
                medianRMSArcsec: 0.4
            ))
        }
        rolls.append(NightSummary(nightDate: start.addingTimeInterval(6 * 86400), medianRMSArcsec: 2.0))
        let ctx = CrossNightContext(profile: profile(), nights: rolls, annotations: [])
        let obs = CrossNightEngine.default.analyze(context: ctx)
        // Should NOT fire — insufficient baseline data
        XCTAssertNil(obs.first { $0.title.contains("Recent RMS above") })
    }

    // MARK: - rig-relative percentiles

    func test_rigBaselineMedianRMS_matchesExpected() {
        let n = (1...11).map { i in
            NightSummary(nightDate: Date(timeIntervalSince1970: Double(i)),
                         medianRMSArcsec: Double(i) * 0.1)
        }
        let ctx = CrossNightContext(profile: profile(), nights: n, annotations: [])
        XCTAssertEqual(ctx.rigBaselineMedianRMS ?? 0, 0.6, accuracy: 0.01)
        XCTAssertEqual(ctx.rigP90RMS ?? 0, 1.0, accuracy: 0.1)
    }
}
