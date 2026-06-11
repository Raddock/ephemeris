import Foundation

/// Lazy extractor for guide-log header fields the 1.x parser doesn't structure.
/// Parses verbatim header lines on demand — non-invasive to the existing model.
///
/// These fields are used by Phase 2 generators that need pointing context, exposure,
/// multi-star state, HFD baseline, and similar header-only data.
nonisolated struct SessionHeaderProperties: Sendable {
    let raHours: Double?
    let decDegrees: Double?
    let hourAngleHours: Double?
    let altitudeDegrees: Double?
    let azimuthDegrees: Double?
    let pierSide: String?
    let hfdPixels: Double?
    let exposureMs: Int?
    let multiStarEnabled: Bool
    let xAngleDegrees: Double?
    let yAngleDegrees: Double?
    let normRateRaArcsecPerSec: Double?
    let normRateDecArcsecPerSec: Double?
    let calibrationOrthogonalityErrorDeg: Double?
    let raGuideSpeedArcsecPerSec: Double?
    let decGuideSpeedArcsecPerSec: Double?
    /// Guide-train focal length from the "Focal length = N mm" line. Post-reducer for OAG.
    let guideFocalLengthMm: Double?
    /// Guide camera pixel pitch from "Camera = ... pixel size = N um".
    let guideCameraPixelSizeMicrons: Double?
    /// Guide-camera binning (1, 2, …) from the "Binning = N" line.
    let guideBinning: Int?
    /// Friendly camera name extracted from "Camera = NAME (...)".
    let guideCameraName: String?
    /// True if the header explicitly reports Variable Exposure Delays enabled.
    /// PHD2 emits this only when the user has enabled it; absence ≠ off, but we treat it
    /// as "unknown / probably off" for the purpose of `VariableExposureDelaysObserver`.
    let variableExposureDelaysEnabled: Bool
    /// Per-axis aggressiveness percentage parsed from
    /// `X guide algorithm = <name>, Aggressiveness = NN.NN, Minimum move = MM.MM`.
    /// The X axis is RA after a normal calibration, Y is Dec.
    let raAggressivenessPercent: Double?
    let decAggressivenessPercent: Double?
    let raGuideAlgorithm: String?
    let decGuideAlgorithm: String?
    let raMinMovePixels: Double?
    let decMinMovePixels: Double?

    init(rawHeader: [String]) {
        var ra: Double?
        var dec: Double?
        var ha: Double?
        var alt: Double?
        var az: Double?
        var pier: String?
        var hfd: Double?
        var expMs: Int?
        var multi = false
        var xAng: Double?
        var yAng: Double?
        var raRate: Double?
        var decRate: Double?
        var orthoErr: Double?
        var raGuide: Double?
        var decGuide: Double?
        var guideFL: Double?
        var guidePixelSize: Double?
        var guideBin: Int?
        var guideCam: String?
        var ved = false
        var xAggro: Double?
        var yAggro: Double?
        var xAlgo: String?
        var yAlgo: String?
        var xMinMove: Double?
        var yMinMove: Double?

        for line in rawHeader {
            if let m = Self.match(line, pattern: #"RA = ([\-\d.]+) hr, Dec = ([\-\d.]+) deg, Hour angle = ([\-\d.]+) hr, Pier side = (\w+)"#) {
                ra = Double(m[0]); dec = Double(m[1]); ha = Double(m[2]); pier = m[3]
            }
            if let m = Self.match(line, pattern: #"Alt = ([\-\d.]+) deg, Az = ([\-\d.]+) deg"#) {
                alt = Double(m[0]); az = Double(m[1])
            }
            if let m = Self.match(line, pattern: #"HFD = ([\d.]+) px"#) {
                hfd = Double(m[0])
            }
            if let m = Self.match(line, pattern: #"Exposure = (\d+) ms"#) {
                expMs = Int(m[0])
            }
            if line.contains("Multi-star mode") {
                multi = true
            }
            if let m = Self.match(line, pattern: #"xAngle = ([\-\d.]+).*yAngle = ([\-\d.]+)"#) {
                xAng = Double(m[0]); yAng = Double(m[1])
            }
            if let m = Self.match(line, pattern: #"Norm rates RA = ([\d.]+)"/s @ dec 0, Dec = ([\d.]+)"/s; ortho\.err\. = ([\d.]+) deg"#) {
                raRate = Double(m[0]); decRate = Double(m[1]); orthoErr = Double(m[2])
            }
            if let m = Self.match(line, pattern: #"RA Guide Speed = ([\d.]+) a-s/s, Dec Guide Speed = ([\d.]+)"#) {
                raGuide = Double(m[0]); decGuide = Double(m[1])
            }
            // PHD2 emits "Camera ... has additional delay setting" / "Variable Exposure Delays" in its header
            // when the feature is enabled. Use a tolerant substring search.
            if line.localizedCaseInsensitiveContains("Variable Exposure Delays") ||
               line.localizedCaseInsensitiveContains("Additional inter-exposure delay") {
                ved = true
            }
            // "Pixel scale = 0.62 arc-sec/px, Binning = 1, Focal length = 1960 mm"
            if let m = Self.match(line, pattern: #"Binning = (\d+), Focal length = (\d+) mm"#) {
                guideBin = Int(m[0])
                guideFL = Double(m[1])
            }
            // "Camera = ZWO ASI174MM Mini (ASCOM), ..., pixel size = 5.9 um"
            if let m = Self.match(line, pattern: #"Camera = ([^,]+),.*pixel size = ([\d.]+) um"#) {
                let rawName = m[0].trimmingCharacters(in: .whitespaces)
                // Strip the " (ASCOM)" / " (Native)" suffix if present
                guideCam = rawName.replacingOccurrences(of: #" \([^)]+\)\s*$"#,
                                                       with: "",
                                                       options: .regularExpression)
                guidePixelSize = Double(m[1])
            }
            // "X guide algorithm = <name>, <settings summary>" — one line per axis;
            // X maps to RA after a normal calibration, Y to Dec. The summary format
            // differs per algorithm (verified against PHD2 upstream GetSettingsSummary):
            //   Hysteresis:   "Hysteresis = 0.100, Aggression = 0.700, Minimum move = 0.200"
            //   ResistSwitch: "Minimum move = 0.150 Aggression = 100% FastSwitch = enabled"
            //   Lowpass2:     "Aggressiveness = 80.000, Minimum move = 0.150"
            //   Lowpass:      "Slope weight = 5.000, Minimum move = 0.200"
            //   ZFilter:      "Type=Bessel-4, Exp-factor=2.0, Minimum move = 0.150"
            // (Predictive PEC writes its summary on follow-on lines, so its
            // aggression/min-move are not attributable to an axis here.)
            if let m = Self.match(line, pattern: #"^X guide algorithm = ([^,]+), (.*)$"#) {
                xAlgo = m[0].trimmingCharacters(in: .whitespaces)
                (xAggro, xMinMove) = Self.parseAlgorithmParams(m[1])
            }
            if let m = Self.match(line, pattern: #"^Y guide algorithm = ([^,]+), (.*)$"#) {
                yAlgo = m[0].trimmingCharacters(in: .whitespaces)
                (yAggro, yMinMove) = Self.parseAlgorithmParams(m[1])
            }
        }

        self.raHours = ra
        self.decDegrees = dec
        self.hourAngleHours = ha
        self.altitudeDegrees = alt
        self.azimuthDegrees = az
        self.pierSide = pier
        self.hfdPixels = hfd
        self.exposureMs = expMs
        self.multiStarEnabled = multi
        self.xAngleDegrees = xAng
        self.yAngleDegrees = yAng
        self.normRateRaArcsecPerSec = raRate
        self.normRateDecArcsecPerSec = decRate
        self.calibrationOrthogonalityErrorDeg = orthoErr
        self.raGuideSpeedArcsecPerSec = raGuide
        self.decGuideSpeedArcsecPerSec = decGuide
        self.guideFocalLengthMm = guideFL
        self.guideCameraPixelSizeMicrons = guidePixelSize
        self.guideBinning = guideBin
        self.guideCameraName = guideCam
        self.variableExposureDelaysEnabled = ved
        self.raAggressivenessPercent = xAggro
        self.decAggressivenessPercent = yAggro
        self.raGuideAlgorithm = xAlgo
        self.decGuideAlgorithm = yAlgo
        self.raMinMovePixels = xMinMove
        self.decMinMovePixels = yMinMove
    }

    /// Convenience derived from min-move and observed pulse stats. Not parsed directly.
    var hasPointingFix: Bool {
        raHours != nil && decDegrees != nil
    }

    /// Parse aggressiveness (normalized to percent) and minimum move from an
    /// algorithm settings summary, tolerating the per-algorithm formats above.
    /// Hysteresis logs aggression as a 0–2 fraction; ResistSwitch as "NN%";
    /// Lowpass2 as a 0–100 "Aggressiveness" value. All normalize to percent.
    private static func parseAlgorithmParams(_ summary: String) -> (aggressivenessPercent: Double?, minMovePixels: Double?) {
        var aggro: Double?
        if let m = match(summary, pattern: #"Aggressiveness = ([\d.]+)"#) {
            aggro = Double(m[0])
        } else if let m = match(summary, pattern: #"Aggression = ([\d.]+)%"#) {
            aggro = Double(m[0])
        } else if let m = match(summary, pattern: #"Aggression = ([\d.]+)"#) {
            aggro = Double(m[0]).map { $0 * 100.0 }
        }
        let minMove = match(summary, pattern: #"Minimum move = ([\d.]+)"#).flatMap { Double($0[0]) }
        return (aggro, minMove)
    }

    /// Match a regex pattern against a line; return the capture groups as strings.
    private static func match(_ line: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let m = regex.firstMatch(in: line, options: [], range: range), m.numberOfRanges >= 2 else { return nil }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            let r = m.range(at: i)
            if r.location == NSNotFound { return nil }
            groups.append(nsLine.substring(with: r))
        }
        return groups
    }
}

extension GuideSession {
    /// Lazily parses additional header fields not structured by the 1.x parser.
    /// Computed on access — generators that don't need these fields don't pay the cost.
    nonisolated var headerProperties: SessionHeaderProperties {
        SessionHeaderProperties(rawHeader: rawHeader)
    }
}
