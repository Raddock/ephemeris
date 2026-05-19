import XCTest
@testable import Ephemeris

/// Tests for RigProfile, MountClass, GuideConfiguration, ImagingScale,
/// SourceAuthority, PHD2Tool, PHD2Algorithm.
///
/// Imaging-scale calculation values are validated against the real Edge-10m corpus
/// header from `~/Desktop/PHD2Logs/` (developer-local): focal length 1960mm,
/// ZWO ASI174MM at 5.9μm, binning 1 → PHD2 reports 0.62 arc-sec/px.
final class RigProfileTests: XCTestCase {

    // MARK: - ImagingScale

    func test_imagingScale_edge10mGuideTrain_matchesCorpus() {
        // PHD2 log reports: "Pixel scale = 0.62 arc-sec/px, Binning = 1, Focal length = 1960 mm"
        // Camera = ZWO ASI174MM Mini, pixel size = 5.9 μm
        let scale = ImagingScale.compute(
            focalLengthMm: 1960,
            pixelSizeMicrons: 5.9,
            binning: 1,
            reducerFactor: nil
        )
        // 206.265 × 5.9 × 1 / 1960 ≈ 0.621 — corpus reports 0.62 (PHD2 rounds to 2dp)
        XCTAssertEqual(scale, 0.621, accuracy: 0.005)
    }

    func test_imagingScale_appliesBinning() {
        let unbinned = ImagingScale.compute(focalLengthMm: 1960, pixelSizeMicrons: 5.9, binning: 1, reducerFactor: nil)
        let binned2 = ImagingScale.compute(focalLengthMm: 1960, pixelSizeMicrons: 5.9, binning: 2, reducerFactor: nil)
        XCTAssertEqual(binned2, unbinned * 2, accuracy: 0.001)
    }

    func test_imagingScale_appliesReducer() {
        let nominal = ImagingScale.compute(focalLengthMm: 2800, pixelSizeMicrons: 3.76, binning: 1, reducerFactor: nil)
        let reduced = ImagingScale.compute(focalLengthMm: 2800, pixelSizeMicrons: 3.76, binning: 1, reducerFactor: 0.7)
        // 0.7 reducer shortens effective FL → larger pixel scale (less sampling)
        XCTAssertEqual(reduced, nominal / 0.7, accuracy: 0.001)
    }

    func test_imagingScale_zeroInputs_returnZero() {
        XCTAssertEqual(ImagingScale.compute(focalLengthMm: 0, pixelSizeMicrons: 5.9, binning: 1, reducerFactor: nil), 0)
        XCTAssertEqual(ImagingScale.compute(focalLengthMm: 1960, pixelSizeMicrons: 0, binning: 1, reducerFactor: nil), 0)
        XCTAssertEqual(ImagingScale.compute(focalLengthMm: 1960, pixelSizeMicrons: 5.9, binning: 0, reducerFactor: nil), 0)
    }

    func test_imagingScale_verdict_tiers() {
        // Imaging scale = 0.4"/px, RMS 0.25" → sub-pixel
        XCTAssertEqual(ImagingScale.verdict(rmsArcsec: 0.25, imagingPixelScale: 0.4), .subPixel)
        // RMS 0.35" / 0.4" = 0.875 → at-resolution
        XCTAssertEqual(ImagingScale.verdict(rmsArcsec: 0.35, imagingPixelScale: 0.4), .atResolution)
        // RMS 0.5" / 0.4" = 1.25 → over-resolution
        XCTAssertEqual(ImagingScale.verdict(rmsArcsec: 0.5, imagingPixelScale: 0.4), .overResolution)
        // No imaging scale → unconfigured
        XCTAssertEqual(ImagingScale.verdict(rmsArcsec: 0.5, imagingPixelScale: 0), .unconfigured)
    }

    func test_imagingScale_verdict_boundaries() {
        // Boundary at 0.7
        XCTAssertEqual(ImagingScale.verdict(rmsArcsec: 0.69, imagingPixelScale: 1.0), .subPixel)
        XCTAssertEqual(ImagingScale.verdict(rmsArcsec: 0.70, imagingPixelScale: 1.0), .atResolution)
        // Boundary at 1.0
        XCTAssertEqual(ImagingScale.verdict(rmsArcsec: 1.00, imagingPixelScale: 1.0), .atResolution)
        XCTAssertEqual(ImagingScale.verdict(rmsArcsec: 1.01, imagingPixelScale: 1.0), .overResolution)
    }

    // MARK: - RigProfile

    func test_rigProfile_defaultsAreEmpty() {
        let p = RigProfile()
        XCTAssertEqual(p.currentName, "")
        XCTAssertEqual(p.nameHistory, [])
        XCTAssertEqual(p.imagingPixelScale, 0)
        XCTAssertFalse(p.isImagingScaleConfigured)
        XCTAssertEqual(p.mountClass, .standardGearMount)
        XCTAssertFalse(p.hasHighPrecisionEncoders)
    }

    func test_rigProfile_edge10m_computesScale() {
        // What the user's rig profile editor would produce once configured for the imaging train.
        // (Imaging train values are user-supplied — guide train values match the corpus headers.)
        var p = RigProfile()
        p.imagingFocalLength = 1960  // same as guide train per the corpus (treat as same-optics for the test)
        p.imagingPixelSize = 5.9
        p.imagingBinning = 1
        p.mountClass = .encoderBasedPremium
        p.hasHighPrecisionEncoders = true
        XCTAssertEqual(p.imagingPixelScale, 0.621, accuracy: 0.005)
        XCTAssertTrue(p.isImagingScaleConfigured)
    }

    func test_rigProfile_rename_recordsHistory() {
        var p = RigProfile(currentName: "Edge-10m")
        p.repairPhd2Name(to: "Edge HD 10m")
        XCTAssertEqual(p.currentName, "Edge HD 10m")
        XCTAssertEqual(p.nameHistory, ["Edge-10m"])

        p.repairPhd2Name(to: "Edge HD 10m")  // no-op
        XCTAssertEqual(p.nameHistory, ["Edge-10m"])

        p.repairPhd2Name(to: "")  // no-op
        XCTAssertEqual(p.currentName, "Edge HD 10m")

        p.repairPhd2Name(to: "  Edge HD 10  ")
        XCTAssertEqual(p.currentName, "Edge HD 10")
        XCTAssertEqual(p.nameHistory, ["Edge-10m", "Edge HD 10m"])
    }

    func test_rigProfile_matches_currentAndHistorical() {
        var p = RigProfile(currentName: "Edge-10m")
        XCTAssertTrue(p.matches(profileName: "Edge-10m"))
        XCTAssertTrue(p.matches(profileName: " Edge-10m "))   // whitespace tolerant
        XCTAssertFalse(p.matches(profileName: "Edge-11"))
        p.repairPhd2Name(to: "Edge HD")
        XCTAssertTrue(p.matches(profileName: "Edge HD"))      // new current
        XCTAssertTrue(p.matches(profileName: "Edge-10m"))     // historical
    }

    func test_rigProfile_codableRoundTrip() throws {
        var original = RigProfile(currentName: "Edge-10m", displayName: "Edge 11 + ASI2600MM (remote obs)")
        original.imagingFocalLength = 1960
        original.imagingPixelSize = 5.9
        original.imagingBinning = 1
        original.guideConfiguration = .oag
        original.guideCameraPixelSize = 5.9
        original.guideFocalLength = 1960
        original.mountClass = .encoderBasedPremium
        original.hasHighPrecisionEncoders = true
        original.notes = "10Micron with 100-pt sky model"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RigProfile.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_rigProfile_effectiveName_prefersDisplayNameWhenSet() {
        var p = RigProfile(currentName: "Edge-10m")
        XCTAssertEqual(p.effectiveName, "Edge-10m")
        p.displayName = "Edge 11 (remote)"
        XCTAssertEqual(p.effectiveName, "Edge 11 (remote)")
        p.displayName = ""   // empty falls back
        XCTAssertEqual(p.effectiveName, "Edge-10m")
        p.displayName = "   "  // whitespace falls back
        XCTAssertEqual(p.effectiveName, "Edge-10m")
    }

    func test_rigProfile_guidePixelScale_sameOpticsUsesImaging() {
        var p = RigProfile()
        p.imagingFocalLength = 1960
        p.imagingPixelSize = 5.9
        p.guideConfiguration = .sameOptics
        // Guide values intentionally different — should be ignored when sameOptics
        p.guideFocalLength = 999
        p.guideCameraPixelSize = 999
        XCTAssertEqual(p.guidePixelScale, p.imagingPixelScale)
    }

    func test_rigProfile_guidePixelScale_oagUsesGuideTrain() {
        var p = RigProfile()
        p.imagingFocalLength = 2800
        p.imagingPixelSize = 3.76
        p.guideConfiguration = .oag
        p.guideFocalLength = 2800   // same OAG path
        p.guideCameraPixelSize = 5.9
        XCTAssertNotEqual(p.guidePixelScale, p.imagingPixelScale)
        XCTAssertEqual(p.guidePixelScale, 206.265 * 5.9 * 1 / 2800, accuracy: 0.001)
    }

    // MARK: - MountClass + defaults

    func test_mountClass_encoderPremium_recommendsLowPass2AndVED() {
        let d = MountClassDefaults.defaults(for: .encoderBasedPremium)
        XCTAssertEqual(d.recommendedRAAlgorithm, .lowpass2)
        XCTAssertEqual(d.recommendedDecAlgorithm, .lowpass2)
        XCTAssertTrue(d.variableExposureDelaysOn)
        XCTAssertTrue(d.backlashCompensationOff)
        XCTAssertEqual(d.sourceAuthority, .phd2Manual)
    }

    func test_mountClass_standardGear_phd2Defaults() {
        let d = MountClassDefaults.defaults(for: .standardGearMount)
        XCTAssertEqual(d.recommendedRAAlgorithm, .hysteresis)
        XCTAssertEqual(d.recommendedDecAlgorithm, .resistSwitch)
        XCTAssertEqual(d.sourceAuthority, .phd2Manual)
    }

    func test_mountClass_harmonic_isCommunityConsensus() {
        let d = MountClassDefaults.defaults(for: .harmonicStrainWave)
        XCTAssertEqual(d.sourceAuthority, .communityConsensus)
        XCTAssertFalse(MountClass.harmonicStrainWave.hasPhd2DocumentedGuidance)
    }

    func test_mountClass_otherClassesHavePhd2Guidance() {
        XCTAssertTrue(MountClass.standardGearMount.hasPhd2DocumentedGuidance)
        XCTAssertTrue(MountClass.encoderBasedPremium.hasPhd2DocumentedGuidance)
        XCTAssertTrue(MountClass.adaptiveOptics.hasPhd2DocumentedGuidance)
    }

    // MARK: - PHD2Algorithm

    func test_phd2Algorithm_logTokens_roundTrip() {
        for alg in PHD2Algorithm.allCases {
            XCTAssertEqual(PHD2Algorithm.fromLogToken(alg.logToken), alg)
        }
    }

    func test_phd2Algorithm_caseInsensitiveParse() {
        XCTAssertEqual(PHD2Algorithm.fromLogToken("lowpass2"), .lowpass2)
        XCTAssertEqual(PHD2Algorithm.fromLogToken("LOWPASS2"), .lowpass2)
        XCTAssertEqual(PHD2Algorithm.fromLogToken("Lowpass2"), .lowpass2)
    }

    func test_phd2Algorithm_deprecationFlags() {
        XCTAssertTrue(PHD2Algorithm.lowpass.isDeprecated)
        XCTAssertTrue(PHD2Algorithm.lowpass.isAgainstRecommendedByPhd2)
        XCTAssertTrue(PHD2Algorithm.zFilter.isAgainstRecommendedByPhd2)
        XCTAssertFalse(PHD2Algorithm.lowpass2.isDeprecated)
        XCTAssertFalse(PHD2Algorithm.lowpass2.isAgainstRecommendedByPhd2)
    }

    // MARK: - PHD2Tool

    func test_phd2Tool_canonicalNamesUsePhd2Capitalization() {
        XCTAssertEqual(PHD2Tool.calibrationAssistant.canonicalName, "Calibration Assistant")
        XCTAssertEqual(PHD2Tool.guidingAssistant.canonicalName, "Guiding Assistant")
        XCTAssertEqual(PHD2Tool.driftAlignment.canonicalName, "Drift Alignment")
        XCTAssertEqual(PHD2Tool.starCross.canonicalName, "Star Cross Tool")
    }

    func test_phd2Tool_hasFourteenEntries() {
        // Per design doc §4, the enum has 14 entries (not 7 as in earlier draft)
        XCTAssertEqual(PHD2Tool.allCases.count, 14)
    }

    func test_phd2Tool_manualUrlsAreValid() {
        for tool in PHD2Tool.allCases {
            let url = tool.manualURL
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "openphdguiding.org")
            XCTAssertTrue(url.fragment != nil || url.absoluteString.contains("#"),
                          "\(tool) should have an anchor")
        }
    }

    // MARK: - SourceAuthority

    func test_sourceAuthority_voiceSoftening() {
        XCTAssertTrue(SourceAuthority.communityConsensus.requiresSoftenedVoice)
        XCTAssertTrue(SourceAuthority.ephemerisHeuristic.requiresSoftenedVoice)
        XCTAssertFalse(SourceAuthority.phd2Manual.requiresSoftenedVoice)
        XCTAssertFalse(SourceAuthority.phd2Measurement.requiresSoftenedVoice)
        XCTAssertFalse(SourceAuthority.phd2BehaviorDocumented.requiresSoftenedVoice)
    }
}
