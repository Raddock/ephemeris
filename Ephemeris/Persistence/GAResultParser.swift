import Foundation

/// Parses Guiding Assistant result INFO entries from a PHD2 log session.
///
/// PHD2 emits a sequence of "INFO: Guiding Assistant: ..." lines when GA stops.
/// Each value is exposed as a separate line; this parser walks the session's infos
/// and aggregates them into a single `GAResultEntity`. Per design §6.2: the
/// recommender's GuidingAssistantRecommendationObserver surfaces these verbatim
/// (`phd2Measurement` source authority) — they supersede any computed estimate.
nonisolated enum GAResultParser {

    /// Parsed result for one GA run. The ingestor maps this to a `GAResultEntity`.
    struct Parsed: Sendable {
        var runAt: Date
        var durationSec: Int = 0
        var recommendedRAMinMovePx: Double?
        var recommendedDecMinMovePx: Double?
        var recommendedExposureSec: Double?
        var polarAlignErrorArcmin: Double?
        var decBacklashMs: Double?
        var raPeakToPeakArcsec: Double?
        var raMaxRateOfChangeArcsecPerSec: Double?
        var highFreqStarMotionArcsecRMS: Double?
        var rawText: String = ""
    }

    /// Walk a session and return zero or more `Parsed` GA results. A session can host
    /// multiple GA runs (rare but possible), so we group by transitions.
    static func parse(session: GuideSession) -> [Parsed] {
        let gaLines = session.infos.filter { $0.text.localizedCaseInsensitiveContains("Guiding Assistant:") }
        guard !gaLines.isEmpty else { return [] }

        // For now, group all GA lines in one session into a single Parsed. (Mostly correct;
        // edge case of two GA runs per session can be split via a heuristic later.)
        var result = Parsed(runAt: session.startedAt ?? .now)
        var rawLines: [String] = []
        for info in gaLines {
            let text = info.text
            rawLines.append(text)

            if let v = extractDouble(text, after: "Suggested RA min-move") {
                result.recommendedRAMinMovePx = v
            }
            if let v = extractDouble(text, after: "Suggested Dec min-move") {
                result.recommendedDecMinMovePx = v
            }
            if let v = extractDouble(text, after: "Suggested exposure") {
                result.recommendedExposureSec = v
            }
            if let v = extractDouble(text, after: "Polar alignment error") {
                result.polarAlignErrorArcmin = v
            }
            if let v = extractDouble(text, after: "Dec backlash") {
                result.decBacklashMs = v
            }
            if let v = extractDouble(text, after: "Peak-to-Peak RA") {
                result.raPeakToPeakArcsec = v
            }
            if let v = extractDouble(text, after: "Max rate of change") {
                result.raMaxRateOfChangeArcsecPerSec = v
            }
            if let v = extractDouble(text, after: "High-frequency star motion") {
                result.highFreqStarMotionArcsecRMS = v
            }
            if let v = extractInt(text, after: "Duration") {
                result.durationSec = v
            }
        }

        guard result.hasAnyMeasurement else { return [] }
        result.rawText = rawLines.joined(separator: "\n")
        return [result]
    }

    /// Pull a Double following a prefix substring. Handles "= 0.18", "= 0.18 px",
    /// ": 0.18", etc. Tolerant of decimal separators and units.
    private static func extractDouble(_ text: String, after prefix: String) -> Double? {
        guard let range = text.range(of: prefix) else { return nil }
        let tail = text[range.upperBound...]
        let scanner = Scanner(string: String(tail))
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " =:\t")
        return scanner.scanDouble()
    }

    private static func extractInt(_ text: String, after prefix: String) -> Int? {
        guard let range = text.range(of: prefix) else { return nil }
        let tail = text[range.upperBound...]
        let scanner = Scanner(string: String(tail))
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " =:\t")
        return scanner.scanInt()
    }
}

private extension GAResultParser.Parsed {
    nonisolated var hasAnyMeasurement: Bool {
        recommendedRAMinMovePx != nil ||
        recommendedDecMinMovePx != nil ||
        recommendedExposureSec != nil ||
        polarAlignErrorArcmin != nil ||
        decBacklashMs != nil ||
        raPeakToPeakArcsec != nil ||
        raMaxRateOfChangeArcsecPerSec != nil ||
        highFreqStarMotionArcsecRMS != nil
    }
}
