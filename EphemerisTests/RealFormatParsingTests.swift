import XCTest
@testable import Ephemeris

/// Pins the parsers to PHD2's *real* line formats, verbatim from real guide logs
/// and PHD2 upstream source (guiding_assistant.cpp `LogResults`, guidinglog.cpp
/// `NotifyGAResult`, and each algorithm's `GetSettingsSummary`). These exist because
/// v2 shipped with parsers matched against invented formats that green unit tests
/// never caught — do not "simplify" these strings; they are the contract.
final class RealFormatParsingTests: XCTestCase {

    // MARK: - GA Result lines (GAResultParser)

    /// The three measurement lines + two recommendation lines a real GA run writes,
    /// copied verbatim from the developer corpus (spacing preserved).
    private let realGARun: [String] = [
        "GA Result - SNR=417.8, Samples=44, Elapsed Time=254s, RA HPF-RMS=  0.17 px (  0.10 arc-sec ), Dec HPF-RMS=  0.07 px (  0.04 arc-sec ), Total HPF-RMS=  0.18 px (  0.11 arc-sec )",
        "GA Result - RA Peak=  0.58 px (  0.36 arc-sec ), RA Peak-Peak   0.61 px (  0.38 arc-sec ), RA Drift Rate= -0.01 px/min ( -0.00 arc-sec/min ), Max RA Drift Rate=  0.02 px/sec (  0.01 arc-sec/sec ), Drift-Limiting Exp=  25.6 s ",
        "GA Result - Dec Drift Rate=  1.00 px/min (  0.61 arc-sec/min ), Dec Peak=  0.91 px (  0.56 arc-sec ), PA Error= 2.3 arc-min",
        "GA Result - Recommendation: Try setting RA min-move to 0.50",
        "GA Result - Recommendation: Try setting Dec min-move to 0.40",
    ]

    private func session(infoTexts: [String]) -> GuideSession {
        var s = GuideSession()
        s.startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        s.infos = infoTexts.enumerated().map { InfoEntry(frame: $0.offset + 1, text: $0.element) }
        return s
    }

    func testGAParserExtractsAllFieldsFromRealRun() throws {
        let parsed = try XCTUnwrap(GAResultParser.parse(session: session(infoTexts: realGARun)).first)
        XCTAssertEqual(parsed.durationSec, 254)
        XCTAssertEqual(try XCTUnwrap(parsed.highFreqStarMotionArcsecRMS), 0.11, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(parsed.raPeakToPeakArcsec), 0.38, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(parsed.raMaxRateOfChangeArcsecPerSec), 0.01, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(parsed.recommendedExposureSec), 25.6, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(parsed.polarAlignErrorArcmin), 2.3, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(parsed.recommendedRAMinMovePx), 0.50, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(parsed.recommendedDecMinMovePx), 0.40, accuracy: 0.001)
    }

    func testGAParserExtractsBacklashMeasurement() throws {
        // Format per guiding_assistant.cpp: "Backlash=" + "<preamble> %d  +/-  %0.0f ms (…)"
        let texts = ["GA Result - Backlash= 320  +/-  40 ms (1.5  +/-  0.2 arc-sec)"]
        let parsed = try XCTUnwrap(GAResultParser.parse(session: session(infoTexts: texts)).first)
        XCTAssertEqual(try XCTUnwrap(parsed.decBacklashMs), 320, accuracy: 0.1)
    }

    func testGAParserExtractsSaturatedBacklash() throws {
        // ">=" preamble when the measurement clipped at 5 s or was impaired.
        let texts = ["GA Result - Backlash=>= 5000  +/-  ms (test impaired)"]
        let parsed = try XCTUnwrap(GAResultParser.parse(session: session(infoTexts: texts)).first)
        XCTAssertEqual(try XCTUnwrap(parsed.decBacklashMs), 5000, accuracy: 0.1)
    }

    func testGuidingAssistantObserverFiresOnRealRun() {
        var log = GuideLog()
        log.guideSessions = [session(infoTexts: realGARun)]
        log.sections = [.guide(0)]
        let profile = RigProfile(currentName: "TestRig")
        let context = SingleNightContext(log: log, profile: profile)

        let observations = GuidingAssistantRecommendationObserver().observe(context: context)
        XCTAssertEqual(observations.count, 1, "GA observer must fire on a real GA Result run")
        let obs = try! XCTUnwrap(observations.first)
        XCTAssertEqual(obs.sourceAuthority, .phd2Measurement)
        XCTAssertTrue(obs.evidence.contains { $0.label.contains("RA min-move") })
        XCTAssertTrue(obs.evidence.contains { $0.label.contains("Polar alignment") })
        XCTAssertTrue(obs.evidence.contains { $0.label.contains("Drift-limiting exposure") })
    }

    func testGuidingAssistantObserverStaysQuietWithoutGALines() {
        var log = GuideLog()
        log.guideSessions = [session(infoTexts: ["DITHER by 1.2, 0.8", "Settling started"])]
        log.sections = [.guide(0)]
        let context = SingleNightContext(log: log, profile: RigProfile(currentName: "TestRig"))
        XCTAssertTrue(GuidingAssistantRecommendationObserver().observe(context: context).isEmpty)
    }

    // MARK: - Algorithm header lines (SessionHeaderProperties)

    func testParsesLowpass2AlgorithmLine() {
        // Verbatim from the developer corpus.
        let props = SessionHeaderProperties(rawHeader: [
            "X guide algorithm = Lowpass2, Aggressiveness = 30.000, Minimum move = 0.400",
            "Y guide algorithm = Lowpass2, Aggressiveness = 40.000, Minimum move = 0.500",
        ])
        XCTAssertEqual(props.raGuideAlgorithm, "Lowpass2")
        XCTAssertEqual(props.decGuideAlgorithm, "Lowpass2")
        XCTAssertEqual(props.raAggressivenessPercent ?? -1, 30.0, accuracy: 0.001)
        XCTAssertEqual(props.decAggressivenessPercent ?? -1, 40.0, accuracy: 0.001)
        XCTAssertEqual(props.raMinMovePixels ?? -1, 0.4, accuracy: 0.001)
        XCTAssertEqual(props.decMinMovePixels ?? -1, 0.5, accuracy: 0.001)
    }

    func testParsesHysteresisAlgorithmLine() {
        // PHD2's default RA algorithm. Aggression logged as a 0–2 fraction
        // (GetSettingsSummary: "Hysteresis = %.3f, Aggression = %.3f, Minimum move = %.3f").
        let props = SessionHeaderProperties(rawHeader: [
            "X guide algorithm = Hysteresis, Hysteresis = 0.100, Aggression = 0.700, Minimum move = 0.200",
        ])
        XCTAssertEqual(props.raGuideAlgorithm, "Hysteresis")
        XCTAssertEqual(props.raAggressivenessPercent ?? -1, 70.0, accuracy: 0.001,
                       "Hysteresis fraction must normalize to percent")
        XCTAssertEqual(props.raMinMovePixels ?? -1, 0.2, accuracy: 0.001)
    }

    func testParsesResistSwitchAlgorithmLine() {
        // PHD2's default Dec algorithm. NOTE: no comma between fields, percent sign on
        // aggression ("Minimum move = %.3f Aggression = %.f%% FastSwitch = %s").
        let props = SessionHeaderProperties(rawHeader: [
            "Y guide algorithm = ResistSwitch, Minimum move = 0.150 Aggression = 100% FastSwitch = enabled",
        ])
        XCTAssertEqual(props.decGuideAlgorithm, "ResistSwitch")
        XCTAssertEqual(props.decAggressivenessPercent ?? -1, 100.0, accuracy: 0.001)
        XCTAssertEqual(props.decMinMovePixels ?? -1, 0.15, accuracy: 0.001)
    }

    func testParsesLowpassAlgorithmLineWithoutAggression() {
        let props = SessionHeaderProperties(rawHeader: [
            "X guide algorithm = Lowpass, Slope weight = 5.000, Minimum move = 0.200",
        ])
        XCTAssertEqual(props.raGuideAlgorithm, "Lowpass")
        XCTAssertNil(props.raAggressivenessPercent)
        XCTAssertEqual(props.raMinMovePixels ?? -1, 0.2, accuracy: 0.001)
    }
}
