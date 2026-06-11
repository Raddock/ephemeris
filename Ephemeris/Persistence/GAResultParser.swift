import Foundation

/// Parses Guiding Assistant result lines from a PHD2 guide-log session.
///
/// When the Guiding Assistant stops, PHD2 writes its measurements and
/// recommendations into the guide log as a run of `INFO: GA Result - …` lines —
/// HPF-RMS, RA/Dec peak and drift, polar-alignment error, and the suggested
/// min-move values. This parser aggregates them into a single `GAResultEntity`.
/// Per design §6.2 the recommender surfaces these verbatim (`phd2Measurement`
/// source authority) — they supersede any computed estimate.
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

        /// True when the run produced actionable guidance (min-move, polar alignment,
        /// backlash, or drift-limiting exposure) as opposed to measurements alone.
        /// Gates the GuidingAssistantRecommendationObserver's observation card.
        var hasRecommendations: Bool {
            recommendedRAMinMovePx != nil ||
            recommendedDecMinMovePx != nil ||
            polarAlignErrorArcmin != nil ||
            decBacklashMs != nil ||
            recommendedExposureSec != nil
        }
    }

    /// Walk a session and return zero or more `Parsed` GA results. A session can host
    /// multiple GA runs (rare but possible), so we group by transitions.
    static func parse(session: GuideSession) -> [Parsed] {
        let gaLines = session.infos.filter { $0.text.contains("GA Result") }
        guard !gaLines.isEmpty else { return [] }

        // For now, group all GA Result lines in one session into a single Parsed.
        // (A session hosting two GA runs is rare; splitting is a future heuristic.)
        var result = Parsed(runAt: session.startedAt ?? .now)
        var rawLines: [String] = []
        for info in gaLines {
            let text = info.text
            rawLines.append(text)

            // Recommendations: "… Recommendation: Try setting RA min-move to 0.50"
            if let v = extractDouble(text, after: "RA min-move to") {
                result.recommendedRAMinMovePx = v
            }
            if let v = extractDouble(text, after: "Dec min-move to") {
                result.recommendedDecMinMovePx = v
            }
            // Polar-alignment error: "… PA Error= 2.3 arc-min"
            if let v = extractDouble(text, after: "PA Error=") {
                result.polarAlignErrorArcmin = v
            }
            // Measurement duration: "… Elapsed Time=138s, …"
            if let v = extractInt(text, after: "Elapsed Time=") {
                result.durationSec = v
            }
            // PHD2 writes the remaining values as "<px> px ( <arcsec> arc-sec )"
            // pairs; keep the arc-sec figure (first number inside the parens).
            if let v = firstParenValue(text, after: "Total HPF-RMS") {
                result.highFreqStarMotionArcsecRMS = v
            }
            if let v = firstParenValue(text, after: "RA Peak-Peak") {
                result.raPeakToPeakArcsec = v
            }
            if let v = firstParenValue(text, after: "Max RA Drift Rate") {
                result.raMaxRateOfChangeArcsecPerSec = v
            }
            // Drift-limiting exposure: "… Drift-Limiting Exp=  25.6 s" — the longest
            // exposure before RA drift dominates; PHD2's effective exposure guidance.
            if let v = extractDouble(text, after: "Drift-Limiting Exp=") {
                result.recommendedExposureSec = v
            }
            // Backlash measurement: "… Backlash= 320  +/-  40 ms (1.5  +/-  0.2 arc-sec)".
            // PHD2 prefixes the value with ">=" when the measurement saturated
            // (>= 5000 ms or too few north points): "Backlash=>= 5000  +/-  ms (…)".
            if let v = extractBacklashMs(text) {
                result.decBacklashMs = v
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

    /// Pull the backlash milliseconds from a "Backlash=" GA line, tolerating the
    /// ">=" saturation preamble PHD2 emits for impaired/clipped measurements.
    private static func extractBacklashMs(_ text: String) -> Double? {
        guard let range = text.range(of: "Backlash=") else { return nil }
        var tail = text[range.upperBound...].drop { $0 == " " }
        if tail.hasPrefix(">=") { tail = tail.dropFirst(2) }
        let scanner = Scanner(string: String(tail))
        scanner.charactersToBeSkipped = .whitespaces
        return scanner.scanDouble()
    }

    /// Pulls the first number inside the parentheses that follow `prefix`. PHD2
    /// writes paired values as "<px> px ( <arcsec> arc-sec )"; we keep the
    /// arc-sec figure. Returns nil if the prefix or a parenthesised number is absent.
    private static func firstParenValue(_ text: String, after prefix: String) -> Double? {
        guard let prefixRange = text.range(of: prefix) else { return nil }
        let tail = text[prefixRange.upperBound...]
        guard let paren = tail.range(of: "(") else { return nil }
        let scanner = Scanner(string: String(tail[paren.upperBound...]))
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " =:\t")
        return scanner.scanDouble()
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
