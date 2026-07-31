import XCTest
@testable import Ephemeris

/// Optional validation tests that run against the developer's real corpus at
/// `~/Desktop/PHD2Logs/`. Skipped automatically when the corpus is not present
/// (e.g., in CI). Provides smoke-level confidence that the recommender produces
/// reasonable output against real PHD2 guide logs.
///
/// Per design doc §13: the corpus is developer-local, never committed.
final class CorpusValidationTests: XCTestCase {

    private var corpusDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Desktop/PHD2Logs", isDirectory: true)
    }

    private var corpusAvailable: Bool {
        FileManager.default.fileExists(atPath: corpusDirectory.path)
    }

    func test_corpus_parsesAllGuideLogs_orSkips() throws {
        guard corpusAvailable else {
            throw XCTSkip("Corpus not present at \(corpusDirectory.path) — skipping.")
        }
        let urls = try corpusGuideLogURLs()
        XCTAssertGreaterThan(urls.count, 0, "Corpus directory exists but contains no PHD2_GuideLog_*.txt files")

        var parsedCount = 0
        var skipReasons: [String: Int] = [:]
        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                skipReasons["unreadable", default: 0] += 1
                continue
            }
            let log = GuideLogParser.parse(text)
            if log.isEmpty {
                skipReasons["empty", default: 0] += 1
                continue
            }
            parsedCount += 1
        }
        print("[Corpus] Parsed \(parsedCount) of \(urls.count) guide logs. Skipped: \(skipReasons)")
        XCTAssertGreaterThan(parsedCount, 0, "No guide logs parsed successfully from the corpus")
    }

    func test_corpus_recommenderFires_orSkips() throws {
        guard corpusAvailable else {
            throw XCTSkip("Corpus not present — skipping.")
        }
        let urls = try corpusGuideLogURLs()
        // Stand-in rig profile for the corpus's Edge-10m setup. Once Phase 3 ships the
        // real RigProfile store this test will pull the real profile.
        var profile = RigProfile(currentName: "Edge-10m")
        profile.imagingFocalLength = 1960
        profile.imagingPixelSize = 5.9
        profile.imagingBinning = 1
        profile.guideConfiguration = .oag
        profile.guideFocalLength = 1960
        profile.guideCameraPixelSize = 5.9
        profile.mountClass = .encoderBasedPremium
        profile.hasHighPrecisionEncoders = true

        var totalObservations = 0
        var byGenerator: [String: Int] = [:]
        var orthoAlerts = 0
        var stalenessAlerts = 0
        var gaRecommendationLogs = 0
        var gaObservationLogs = 0
        var algoHeaderSessions = 0
        var algoParsedSessions = 0

        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let log = GuideLogParser.parse(text)
            guard !log.isEmpty else { continue }
            let observations = RecommenderEngine.default.analyze(log: log, profile: profile)
            totalObservations += observations.count
            for obs in observations {
                let key = obs.title
                byGenerator[key, default: 0] += 1
                if obs.title.contains("orthogonality") && obs.severity == .alert { orthoAlerts += 1 }
                if obs.title.contains("Calibration is") && obs.severity == .hygiene { stalenessAlerts += 1 }
            }

            // Real-format regression guards. These paths shipped dead once because
            // unit fixtures used invented line formats — assert against the real
            // corpus so a format mismatch can never pass silently again.
            if text.contains("GA Result - Recommendation") {
                gaRecommendationLogs += 1
                if observations.contains(where: { $0.title.contains("Guiding Assistant") }) {
                    gaObservationLogs += 1
                }
            }
            for session in log.guideSessions
            where session.rawHeader.contains(where: { $0.hasPrefix("X guide algorithm =") }) {
                algoHeaderSessions += 1
                if session.headerProperties.raGuideAlgorithm != nil,
                   session.headerProperties.raMinMovePixels != nil {
                    algoParsedSessions += 1
                }
            }
        }

        if gaRecommendationLogs > 0 {
            XCTAssertEqual(gaObservationLogs, gaRecommendationLogs,
                           "Logs with GA recommendations must produce a Guiding Assistant observation")
        }
        if algoHeaderSessions > 0 {
            XCTAssertEqual(algoParsedSessions, algoHeaderSessions,
                           "Sessions with algorithm header lines must parse algorithm + min-move")
        }
        print("[Corpus] GA logs: \(gaRecommendationLogs), GA observations fired: \(gaObservationLogs)")
        print("[Corpus] Algo header sessions: \(algoHeaderSessions), parsed: \(algoParsedSessions)")

        print("[Corpus] Total observations: \(totalObservations) across \(urls.count) logs")
        print("[Corpus] Per-title breakdown:")
        for (title, count) in byGenerator.sorted(by: { $0.value > $1.value }) {
            print("  \(count) × \(title)")
        }
        print("[Corpus] Orthogonality alerts (>10°): \(orthoAlerts)")
        print("[Corpus] Calibration-staleness alerts (>30d): \(stalenessAlerts)")

        // Sanity expectations from the corpus analysis:
        // - 56% of pooled sessions show >5° ortho (the 12.2° calibration was used widely);
        //   so we should see at least some orthogonality alerts across the corpus.
        // - The corpus has 4 cals across 4 months → many sessions with >30 day cal age.
        //   We should see some staleness alerts.
        XCTAssertGreaterThan(totalObservations, 0,
                             "Recommender produced no observations on \(urls.count) real logs")
    }

    /// Pins the session-anchoring contract: generators whose evidence comes from
    /// one session must stamp `sessionStartedAt` with a real session start, and
    /// night-level generators must leave it nil. The inspector's per-session
    /// filtering depends on this — an unanchored per-session observation would
    /// silently vanish from every session view.
    func test_corpus_sessionScopedObservations_carrySessionAnchor() throws {
        guard corpusAvailable else {
            throw XCTSkip("Corpus not present — skipping.")
        }
        var profile = RigProfile(currentName: "Edge-10m")
        profile.imagingFocalLength = 1960
        profile.imagingPixelSize = 5.9
        profile.imagingBinning = 1
        profile.guideConfiguration = .oag
        profile.guideFocalLength = 1960
        profile.guideCameraPixelSize = 5.9
        profile.mountClass = .encoderBasedPremium
        profile.hasHighPrecisionEncoders = true

        let perSessionGenerators: [any RecommenderGenerator] = [
            GuidingAssistantRecommendationObserver(),
            CalibrationSanityAlertObserver(),
            MaxDurationLimitObserver(),
            DecPolarityBiasObserver(),
            AtmosphericConditionsProxy(),
        ]
        let nightLevelGenerators: [any RecommenderGenerator] = [
            CalibrationStalenessObserver(),
            CalibrationOrthogonalityObserver(),
            StarShapePredictionObserver(),
            DataDrivenAlgorithmHintObserver(),
            MinMoveValidationObserver(),
            GuideRateValidationObserver(),
            AggressivenessObserver(),
            PierSideBiasObserver(),
            CooldownSignatureObserver(),
            GuideScaleMismatchObserver(),
            StarLostObserver(),
            VariableExposureDelaysObserver(),
            MultiStarGuidingObserver(),
            AlgorithmMismatchObserver(),
        ]

        // The classification above must cover the default engine exactly — a
        // generator added to the engine without being classified here would
        // escape the contract.
        let classified = Set((perSessionGenerators + nightLevelGenerators).map { $0.identifier })
        let registered = Set(RecommenderEngine.default.generators.map { $0.identifier })
        XCTAssertEqual(classified, registered,
                       "Generator classification is out of sync with RecommenderEngine.default — unclassified: \(registered.subtracting(classified)), stale: \(classified.subtracting(registered))")

        var anchoredCount = 0
        for url in try corpusGuideLogURLs() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let log = GuideLogParser.parse(text)
            guard !log.isEmpty else { continue }
            let context = SingleNightContext(log: log, profile: profile)
            let sessionStarts = Set(log.guideSessions.compactMap(\.startedAt))

            for generator in perSessionGenerators {
                for obs in generator.observe(context: context) {
                    let anchor = try XCTUnwrap(
                        obs.sessionStartedAt,
                        "\(generator.identifier) emitted an unanchored observation (\(obs.title)) in \(url.lastPathComponent)")
                    XCTAssertTrue(sessionStarts.contains(anchor),
                                  "\(generator.identifier) anchored to a time that isn't a session start in \(url.lastPathComponent)")
                    anchoredCount += 1
                }
            }
            for generator in nightLevelGenerators {
                for obs in generator.observe(context: context) {
                    XCTAssertNil(obs.sessionStartedAt,
                                 "\(generator.identifier) is night-level and must not claim a session (\(obs.title))")
                }
            }
        }
        XCTAssertGreaterThan(anchoredCount, 0,
                             "Corpus produced no session-anchored observations — the anchoring path went untested")
        print("[Corpus] Session-anchored observations verified: \(anchoredCount)")
    }

    private func corpusGuideLogURLs() throws -> [URL] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: corpusDirectory, includingPropertiesForKeys: nil)
        return contents
            .filter { $0.lastPathComponent.hasPrefix("PHD2_GuideLog_") && $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
