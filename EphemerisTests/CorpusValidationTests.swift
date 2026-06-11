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
                if obs.title.contains("Calibration is") && obs.severity == .alert { stalenessAlerts += 1 }
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

    private func corpusGuideLogURLs() throws -> [URL] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: corpusDirectory, includingPropertiesForKeys: nil)
        return contents
            .filter { $0.lastPathComponent.hasPrefix("PHD2_GuideLog_") && $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
