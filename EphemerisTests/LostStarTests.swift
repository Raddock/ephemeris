//
//  LostStarTests.swift
//  EphemerisTests
//
//  Copyright (C) 2026 Andrew Burwell
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import Testing
@testable import Ephemeris

/// The recommender's handling of sessions where guiding lost the star, and of
/// ASIAir logs. On a customer's ASIAir night a mount that stopped tracking let
/// the star run 1,300 px from the lock position; the recommender called that
/// "elevated RMS, likely atmospheric" and drew other diagnoses from it.
struct LostStarTests {

    /// One guide frame: distance from lock (px) and the RA correction sent (ms).
    struct Frame {
        var ra: Double
        var dec: Double = 0
        var raMs: Int = 0
        var decMs: Int = 0
        var mass: Int = 1000
        /// A frame where PHD2 couldn't measure the star (ErrorCode 2).
        var dropped = false
        /// An INFO line written just before this frame.
        var infoBefore: String? = nil
    }

    static func good(_ count: Int, rms: Double = 0.2, mass: (Int) -> Int = { _ in 1000 }) -> [Frame] {
        (0..<count).map { i in Frame(ra: i.isMultiple(of: 2) ? rms : -rms, raMs: 100, mass: mass(i)) }
    }

    /// A star moving steadily away from the lock position.
    static func runaway(_ count: Int, from start: Double, step: Double, raMs: Int = 2500) -> [Frame] {
        (0..<count).map { i in Frame(ra: start + Double(i) * step, raMs: raMs) }
    }

    /// Builds a guide log in PHD2's format and parses it with the real parser.
    static func makeLog(asiAir: Bool = false, searchRegion: Int? = 50, scale: Double = 3.15,
                        multiStar: Bool = false, sessions: [[Frame]]) -> GuideLog {
        GuideLogParser.parse(makeLogText(asiAir: asiAir, searchRegion: searchRegion, scale: scale,
                                         multiStar: multiStar, sessions: sessions))
    }

    static func makeLogText(asiAir: Bool = false, searchRegion: Int? = 50, scale: Double = 3.15,
                            multiStar: Bool = false, sessions: [[Frame]]) -> String {
        let banner = asiAir
            ? "PHD2 version, Log version 2.5. Log enabled at 2026-11-01 20:00:00"
            : "PHD2 version 2.6.13 [macOS], Log version 2.5. Log enabled at 2026-11-01 20:00:00"
        var text = banner + "\n"
        for (index, frames) in sessions.enumerated() {
            let regionLine: String
            if let searchRegion {
                regionLine = "Search region = \(searchRegion) px, Star mass tolerance = 50.0%" + (multiStar ? ", Multi-star mode, list size = 9" : "")
            } else {
                regionLine = "Star mass tolerance = 50.0%"
            }
            text += """

            Guiding Begins at 2026-11-01 20:\(String(format: "%02d", index * 10)):00
            Dither = both axes, Dither scale = 1.000, Image noise reduction = none, Guide-frame time lapse = 0, Server enabled
            Pixel scale = \(scale) arc-sec/px, Binning = 1, Focal length = 384 mm
            \(regionLine)
            Equipment Profile = \(asiAir ? "" : "Test Rig")
            Camera = ZWO ASI174MM Mini, gain = 400, full size = 1936 x 1216, no dark, no defect map, pixel size = 5.9 um
            Exposure = 2000 ms
            Mount = Test Mount,  connected, guiding enabled, xAngle = 0.0, xRate = 1.000, yAngle = 90.0, yRate = 1.000, parity = +/+,
            X guide algorithm = Hysteresis, Hysteresis = 0.100, Aggression = 0.750, Minimum move = 0.100
            Y guide algorithm = Resist Switch, Minimum move = 0.100 Aggression = 75% FastSwitch = enabled
            Calibration step = 750, Max RA duration = 2500, Max DEC duration = 2500, DEC guide mode = Auto
            Dec = 20.0 deg, Hour angle = 0.50 hr, Pier side = East, Rotator pos = Unknown
            Frame,Time,mount,dx,dy,RARawDistance,DECRawDistance,RAGuideDistance,DECGuideDistance,RADuration,RADirection,DECDuration,DECDirection,XStep,YStep,StarMass,SNR,ErrorCode

            """
            for (i, f) in frames.enumerated() {
                if let info = f.infoBefore { text += "INFO: \(info)\n" }
                if f.dropped {
                    text += "\(i + 1),\(Double(i) * 2.0),\"DROP\",,,,,,,,,,,,,0,0.00,2,\"Star lost - low SNR\"\n"
                    continue
                }
                let raDir = f.raMs == 0 ? "" : "E"
                let decDir = f.decMs == 0 ? "" : "N"
                text += "\(i + 1),\(Double(i) * 2.0),\"Mount\",0,0,\(f.ra),\(f.dec),0,0,\(f.raMs),\(raDir),\(f.decMs),\(decDir),,,\(f.mass),30.00,0\n"
            }
            text += "Guiding Ends at 2026-11-01 20:\(String(format: "%02d", index * 10 + 5)):00\n"
        }
        return text
    }

    // MARK: - Detection

    @Test func runawayAtTheEndIsFound() throws {
        let log = Self.makeLog(sessions: [Self.good(30) + Self.runaway(10, from: 60, step: 60)])
        let run = try #require(LostStar.detect(in: log.guideSessions[0]))
        #expect(run.firstEntryIndex == 30)
        #expect(run.frames == 10)
        #expect(run.startDistancePx == 60)
        #expect(run.maxDistancePx == 600)
        #expect(run.searchRegionPx == 50)
        #expect(run.raCorrectedFrames == 10)
        // "Max RA duration" sits on the Calibration step line, as PHD2 2.6 and
        // the ASIAir write it, not on the Mount line the header parser reads.
        #expect(run.maxRADurationMs == 2500)
        #expect(run.raMaxedFrames == 10)
    }

    @Test func steadyOffsetPastTheRegionIsNotLost() {
        // NINA logs end some sessions mid-settle after a dither: the star sits
        // a few px beyond a 15 px search region without moving.
        let steady = (0..<15).map { i in Frame(ra: 17 + Double(i % 2)) }
        let log = Self.makeLog(searchRegion: 15, sessions: [Self.good(30) + steady])
        #expect(LostStar.detect(in: log.guideSessions[0]) == nil)
    }

    @Test func excursionThatComesBackIsNotLost() {
        let log = Self.makeLog(sessions: [Self.good(30) + Self.runaway(10, from: 80, step: 25) + Self.good(5)])
        #expect(LostStar.detect(in: log.guideSessions[0]) == nil)
    }

    @Test func runShorterThanFiveFramesIsNotLost() {
        let log = Self.makeLog(sessions: [Self.good(30) + Self.runaway(4, from: 60, step: 200)])
        #expect(LostStar.detect(in: log.guideSessions[0]) == nil)
    }

    @Test func driftWithNoCorrectionsIsLostAndSaysSo() throws {
        let log = Self.makeLog(searchRegion: 15, sessions: [Self.good(30) + Self.runaway(10, from: 20, step: 7, raMs: 0)])
        let run = try #require(LostStar.detect(in: log.guideSessions[0]))
        #expect(run.raCorrectedFrames == 0)

        let observation = try #require(LostStarObserver().observe(
            context: SingleNightContext(log: log, profile: RigProfile(currentName: "Test Rig"))).first)
        #expect(observation.summary.contains("None of those 10 frames sent a guide correction on either axis"))
        #expect(observation.summary.contains("guiding output was most likely paused or turned off"))
    }

    // MARK: - Codex review cases

    @Test func driftWithGuidingOutputTurnedOffIsNotLost() {
        // The Guiding Assistant turns guiding output off and measures the drift.
        var drift = Self.runaway(10, from: 20, step: 10, raMs: 0)
        drift[0].infoBefore = "Guiding parameter change, MountGuidingEnabled = false"
        let log = Self.makeLog(searchRegion: 15, sessions: [Self.good(30) + drift])
        #expect(LostStar.detect(in: log.guideSessions[0]) == nil)
    }

    @Test func guidingAssistantResultsSurviveTheCut() {
        var tail = Self.runaway(10, from: 60, step: 60)
        tail[5].infoBefore = "GA Result - Recommendation: Try setting RA min-move to 0.25"
        let log = Self.makeLog(sessions: [Self.good(30) + tail])
        #expect(LostStar.detect(in: log.guideSessions[0]) != nil)
        let context = SingleNightContext(log: log, profile: RigProfile(currentName: "Test Rig"))
        let fromRaw = GuidingAssistantRecommendationObserver().observe(context: context)
        let expected = GAResultParser.parse(session: log.guideSessions[0]).count
        #expect(expected > 0)
        #expect(fromRaw.count == expected)
    }

    @Test func singleSpikeDoesNotTurnASteadyOffsetIntoARunaway() {
        let tail = [17.0, 18, 40, 18, 17].map { Frame(ra: $0, raMs: 100) }
        let log = Self.makeLog(searchRegion: 15, sessions: [Self.good(30) + tail])
        #expect(LostStar.detect(in: log.guideSessions[0]) == nil)
    }

    @Test func decCorrectionsAreNotReadAsGuidingOff() throws {
        let tail = (0..<10).map { i in Frame(ra: 0, dec: 60 + Double(i) * 60, raMs: 0, decMs: 2500) }
        let log = Self.makeLog(sessions: [Self.good(30) + tail])
        let run = try #require(LostStar.detect(in: log.guideSessions[0]))
        #expect(run.raCorrectedFrames == 0)
        #expect(run.decCorrectedFrames == 10)
        let summary = try #require(LostStarObserver().observe(
            context: SingleNightContext(log: log, profile: RigProfile(currentName: "Test Rig"))).first).summary
        #expect(!summary.contains("paused"))
        #expect(summary.contains("All 10 of those frames sent a guide correction"))
    }

    @Test func lengthRunsToTheSessionEndThroughUnmeasuredFrames() throws {
        let lost = Self.runaway(10, from: 60, step: 60) + (0..<150).map { _ in Frame(ra: 0, dropped: true) }
        let log = Self.makeLog(sessions: [Self.good(30) + lost])
        let run = try #require(LostStar.detect(in: log.guideSessions[0]))
        #expect(run.unmeasuredFrames == 150)
        // 160 frames 2 s apart: 318 s from the run's first frame, not 18 s.
        #expect(run.durationSec == 318)
        let summary = try #require(LostStarObserver().observe(
            context: SingleNightContext(log: log, profile: RigProfile(currentName: "Test Rig"))).first).summary
        #expect(summary.hasPrefix("For the last 5.3 minutes"))
        #expect(summary.contains("couldn't measure the star in 150 frames"))
    }

    // MARK: - Second Codex review cases

    @Test func nonFiniteAndHugeDistancesNeverTrap() throws {
        // A malformed row can parse to inf; a corrupt one to 1e300.
        for bad in [Double.infinity, 1e300] {
            let tail = [20.0, 30, bad, 50, 60, 75].map { Frame(ra: $0, raMs: 2500) }
            let log = Self.makeLog(searchRegion: 15, sessions: [Self.good(30) + tail])
            let observations = LostStarObserver().observe(
                context: SingleNightContext(log: log, profile: RigProfile(currentName: "Test Rig")))
            #expect(observations.count == 1)
            #expect(observations.first.map { !$0.summary.contains("inf") } == true)
        }
    }

    @Test func mergedSessionsAreNotJudged() {
        // A merged session keeps only its first source session's header, so
        // the search region for its last session is unknown: two steady
        // offsets chained across the join would otherwise read as 17 to 34 px.
        let steady = Self.makeLog(searchRegion: 15, sessions: [
            Self.good(20) + (0..<6).map { _ in Frame(ra: 17, raMs: 100) },
            (0..<10).map { _ in Frame(ra: 34, raMs: 100) },
        ])
        let merged = GuideSessionMerger.merge(steady.guideSessions)
        #expect(merged.entries.contains { $0.raRawDistance.isNaN })
        #expect(LostStar.detect(in: merged) == nil)

        // Even a real runaway is left to the per-session view, which has the
        // right header.
        let runaway = Self.makeLog(sessions: [Self.good(30), Self.good(30) + Self.runaway(10, from: 60, step: 60)])
        #expect(LostStar.detect(in: runaway.guideSessions[1]) != nil)
        #expect(LostStar.detect(in: GuideSessionMerger.merge(runaway.guideSessions)) == nil)
    }

    @Test func smallestPossibleDurationNeverTraps() throws {
        // Fourth Codex round: a damaged row with RADuration = Int.min and
        // direction E parses as Int.min, and abs(Int.min) traps.
        var tail = Self.runaway(10, from: 60, step: 60)
        tail[4].raMs = Int.min
        let log = Self.makeLog(sessions: [Self.good(30) + tail])
        let run = try #require(LostStar.detect(in: log.guideSessions[0]))
        #expect(run.raMaxedFrames == 10)
    }

    @Test func corruptTimestampsNeverTrap() throws {
        // The parser accepts "nan" and huge values in the Time field.
        for badTime in ["nan", "1e300"] {
            var text = Self.makeLogText(sessions: [Self.good(30) + Self.runaway(10, from: 60, step: 60)])
            let lastRow = try #require(text.range(of: "40,78.0,"))
            text.replaceSubrange(lastRow, with: "40,\(badTime),")
            let log = GuideLogParser.parse(text)
            let observations = LostStarObserver().observe(
                context: SingleNightContext(log: log, profile: RigProfile(currentName: "Test Rig")))
            #expect(observations.count == 1)
            let run = try #require(LostStar.detect(in: log.guideSessions[0]))
            #expect(run.durationSec.isFinite)
        }
    }

    @Test func calibrationAlertsSurviveADroppedSession() {
        var frames = Self.good(3) + Self.runaway(10, from: 60, step: 60)
        frames[1].infoBefore = "Too few steps for calibration"
        let log = Self.makeLog(sessions: [frames])
        let context = SingleNightContext(log: log, profile: RigProfile(currentName: "Test Rig"))
        #expect(context.sessions.isEmpty)   // the session itself was dropped
        #expect(CalibrationSanityAlertObserver().observe(context: context).count == 1)
    }

    @Test func searchRegionDefaultsToPHD2Default() throws {
        let log = Self.makeLog(searchRegion: nil, sessions: [Self.good(30) + Self.runaway(10, from: 20, step: 10)])
        #expect(try #require(LostStar.detect(in: log.guideSessions[0])).searchRegionPx == 15)
    }

    // MARK: - Analysis view

    @Test func analysisViewCutsLostStretchesAndDropsSessionsWithLittleLeft() {
        let log = Self.makeLog(sessions: [
            Self.good(30) + Self.runaway(10, from: 60, step: 60),   // cut to 30 frames
            Self.good(3) + Self.runaway(10, from: 60, step: 60),    // 3 left: dropped
            Self.good(40),                                           // untouched
        ])
        let (view, findings) = LostStar.analysisView(of: log)
        #expect(findings.count == 2)
        #expect(view.guideSessions.count == 2)
        #expect(view.guideSessions.map(\.entries.count) == [30, 40])
        #expect(view.sections == [.guide(0), .guide(1)])
        // The parsed log itself is untouched.
        #expect(log.guideSessions.map(\.entries.count) == [40, 13, 40])
    }

    @Test func engineReportsTheStretchInsteadOfDiagnosingIt() throws {
        // A runaway with high star-mass variability: before the fix this read
        // as "Elevated RMS, likely atmospheric".
        let wobbly: (Int) -> Int = { $0.isMultiple(of: 2) ? 500 : 1500 }
        let log = Self.makeLog(sessions: [Self.good(3) + Self.runaway(40, from: 60, step: 30).map {
            var f = $0; f.mass = wobbly(Int($0.ra)); return f
        }])
        let observations = RecommenderEngine.default.analyze(log: log, profile: RigProfile(currentName: "Test Rig"))
        let start = log.guideSessions[0].startedAt
        let anchored = observations.filter { $0.sessionStartedAt == start }
        #expect(anchored.map(\.title) == ["Guiding lost the star"])
        #expect(anchored.first?.sourceAuthority == .ephemerisHeuristic)
    }

    // MARK: - Atmospheric conditions proxy

    private func atmospheric(rmsPx: Double, scale: Double) -> [RecommenderObservation] {
        let log = Self.makeLog(scale: scale, sessions: [Self.good(60, rms: rmsPx, mass: { $0.isMultiple(of: 2) ? 500 : 1500 })])
        return AtmosphericConditionsProxy().observe(
            context: SingleNightContext(log: log, profile: RigProfile(currentName: "Test Rig")))
    }

    @Test func atmosphereNeedsHalfAGuidePixelToCallRMSElevated() {
        // 0.3 px at 3.15″/px is 0.95″: over the old 0.7″ bar, but a third of a
        // guide pixel, which is good guiding on a short guide scope.
        #expect(atmospheric(rmsPx: 0.3, scale: 3.15).isEmpty)
        // 0.6 px at 3.15″/px is 1.9″: elevated, and with variable star mass it fires.
        #expect(atmospheric(rmsPx: 0.6, scale: 3.15).count == 1)
    }

    @Test func atmosphereIsNeverBlamedForTensOfArcseconds() {
        // 3 px at 3.15″/px is 9.5″: beyond anything seeing does to a centroid.
        #expect(atmospheric(rmsPx: 3.0, scale: 3.15).isEmpty)
    }

    @Test func atmosphereUnchangedOnAFineGuideScale() {
        // On the 0.62″/px train the 0.7″ bar was calibrated on, half a pixel is
        // 0.31″, so the old bar still decides: 1.3 px is 0.81″ and fires.
        #expect(atmospheric(rmsPx: 1.3, scale: 0.62).count == 1)
    }

    // MARK: - Cooldown

    @Test func failedStartIsNotTheNightsFirstSession() {
        let night = [Self.good(3, rms: 20)] + (0..<3).map { _ in Self.good(40, rms: 0.3) }
        let log = Self.makeLog(sessions: night)
        let observations = CooldownSignatureObserver().observe(
            context: SingleNightContext(log: log, profile: RigProfile(currentName: "Test Rig")))
        #expect(observations.isEmpty)
    }

    @Test func realFirstSessionStillShowsCooldown() {
        let night = [Self.good(40, rms: 1.0)] + (0..<3).map { _ in Self.good(40, rms: 0.3) }
        let log = Self.makeLog(sessions: night)
        let observations = CooldownSignatureObserver().observe(
            context: SingleNightContext(log: log, profile: RigProfile(currentName: "Test Rig")))
        #expect(observations.count == 1)
    }

    // MARK: - ASIAir

    @Test func asiAirIsRecognizedByItsBanner() {
        #expect(GuideLogParser.parse(ASIAirFormatTests.log).isASIAir)
        #expect(!Self.makeLog(sessions: [Self.good(30)]).isASIAir)
        #expect(!GuideLogParser.parse("Guiding Begins at 2026-11-01 20:00:00\n").isASIAir)
    }

    @Test func multiStarIsNotInferredFromAnASIAirHeader() {
        let profile = RigProfile(currentName: "Test Rig")
        let titles = { (log: GuideLog) in RecommenderEngine.default.analyze(log: log, profile: profile).map(\.title) }
        #expect(!titles(Self.makeLog(asiAir: true, sessions: [Self.good(60)])).contains("Multi-star guiding not enabled"))
        #expect(titles(Self.makeLog(asiAir: false, sessions: [Self.good(60)])).contains("Multi-star guiding not enabled"))
        #expect(!titles(Self.makeLog(asiAir: false, multiStar: true, sessions: [Self.good(60)])).contains("Multi-star guiding not enabled"))
    }

    @Test func asiAirAdviceNamingPHD2ControlsGetsTheNote() {
        let withTool = RecommenderObservation(
            scope: .singleNight, rigProfileId: UUID(), nightRecordIds: [],
            category: .suggestion, severity: .suggestion,
            title: "t", summary: "s", evidence: [], candidateContributors: [],
            suggestedResponse: "Run the Guiding Assistant.",
            relatedHelpTopicIds: [], relatedPHD2Tools: [.guidingAssistant],
            confidence: .medium, sourceAuthority: .ephemerisHeuristic)
        var noLever = withTool
        noLever.relatedPHD2Tools = []
        noLever.suggestedResponse = "Not a PHD2 lever."

        let noted = RecommenderEngine.notingASIAir(withTool)
        #expect(noted.suggestedResponse.hasSuffix(RecommenderEngine.asiAirNote))
        // Applied once, and only where a PHD2 control is named.
        #expect(RecommenderEngine.notingASIAir(noted).suggestedResponse == noted.suggestedResponse)
        #expect(RecommenderEngine.notingASIAir(noLever).suggestedResponse == "Not a PHD2 lever.")
    }
}
