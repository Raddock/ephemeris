//
//  ASIAirFormatTests.swift
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

/// ZWO's ASIAir writes a "PHD2 compatible" guide log that differs from PHD2's
/// own in a few header lines: no PHD2 version number in the banner, a blank
/// Equipment Profile, no `RA = ` field on the pointing line, no `Norm rates`
/// line, and no `Guiding Ends` after the last session. The values below are
/// synthetic; the line shapes follow a real ASIAir log (October 2026).
struct ASIAirFormatTests {

    static let log = """
    PHD2 version, Log version 2.5. Log enabled at 2026-10-16 19:30:46

    Calibration Begins at 2026-10-16 19:30:46
    Equipment Profile =
    Camera = ZWO ASI120MC-S
    Exposure = 1500 ms
    Pixel scale = 6.45 arc-sec/px, Binning = 1, Focal length = 120 mm
    Mount = EQMod Mount, Calibration Step = 2000 ms, Assume orthogonal axes = no
    Dec = 15.5 deg, Hour angle = 0.15 hr, Pier side = West, Rotator pos = Unknown
    Lock position = 76.500, 209.600, Star position = 76.700, 210.300, HFD = 3.70 px
    Direction,Step,dx,dy,x,y,Dist
    West,0,0.000,0.000,77.000,211.000,0.000
    West,1,-4.000,-0.200,81.000,211.200,4.005
    West calibration complete. Angle = -178.0 deg, Rate = 2.300 px/sec, Parity = Even
    North,0,0.000,0.000,85.000,215.000,0.000
    North,1,0.500,2.700,84.500,212.300,2.746
    North calibration complete. Angle = -101.0 deg, Rate = 1.500 px/sec, Parity = Even
    Calibration complete, mount = EQMod Mount.

    Guiding Begins at 2026-10-16 19:32:59
    Dither = both axes, Dither scale = 1.000, Image noise reduction = none, Guide-frame time lapse = 0, Server enabled
    Pixel scale = 6.45 arc-sec/px, Binning = 1, Focal length = 120 mm
    Search region = 50 px, Star mass tolerance = 50.0%
    Equipment Profile =
    Camera = ZWO ASI120MC-S, gain = 66, full size = 1280 x 960, no dark, no defect map, pixel size = 3.8 um
    Exposure = 1500 ms
    Mount = EQMod Mount,  connected, guiding enabled, xAngle = -178.0, xRate = 2.300, yAngle = -101.0, yRate = 1.500, parity = +/+,
    X guide algorithm = Hysteresis, Hysteresis = 0.100, Aggression = 0.750, Minimum move = 0.100
    Y guide algorithm = Resist Switch, Minimum move = 0.100 Aggression = 85% FastSwitch = enabled
    Backlash comp = disabled, pulse = 0 ms
    Calibration step = phdlab_placeholder, Max RA duration = 2000, Max DEC duration = 2000, DEC guide mode = Auto
    RA Guide Speed = 13.5 a-s/s, Dec Guide Speed = 13.5 a-s/s, Cal Dec = 15.6, Last Cal Issue = Orthogonality, Timestamp = Unknown
    Dec = 15.6 deg, Hour angle = 0.19 hr, Pier side = West, Rotator pos = Unknown
    Lock position = 76.500, 209.600, Star position = 85.300, 208.300, HFD = 3.67 px
    Frame,Time,mount,dx,dy,RARawDistance,DECRawDistance,RAGuideDistance,DECGuideDistance,RADuration,RADirection,DECDuration,DECDirection,XStep,YStep,StarMass,SNR,ErrorCode
    INFO: SETTLING STATE CHANGE, Settling started
    1,1.250,"Mount",-0.100,0.400,0.100,-0.400,0.000,-0.300,0,,200,N,,,1500,27.00,0
    2,2.500,"Mount",-0.200,0.500,0.200,-0.500,0.100,-0.400,40,W,250,N,,,1600,28.00,0
    INFO: SETTLING STATE CHANGE, Settling failed
    Guiding Ends at 2026-10-16 19:36:56

    Guiding Begins at 2026-10-16 19:38:56
    Pixel scale = 6.45 arc-sec/px, Binning = 1, Focal length = 120 mm
    Equipment Profile =
    Exposure = 1500 ms
    Mount = EQMod Mount,  connected, guiding enabled, xAngle = -178.0, xRate = 2.040, yAngle = -101.0, yRate = 1.500, parity = +/+,
    Dec = 31.2 deg, Hour angle = -0.93 hr, Pier side = East, Rotator pos = Unknown
    Frame,Time,mount,dx,dy,RARawDistance,DECRawDistance,RAGuideDistance,DECGuideDistance,RADuration,RADirection,DECDuration,DECDirection,XStep,YStep,StarMass,SNR,ErrorCode
    1,1.250,"Mount",-0.100,0.400,0.100,-0.400,0.000,-0.300,0,,200,N,,,1500,27.00,0
    2,2.500,"Mount",-0.200,0.500,0.200,-0.500,0.100,-0.400,40,W,250,N,,,1600,28.00,0
    3,3.750,"Mount",-0.150,0.450,0.150,-0.450,0.050,-0.350,30,W,220,N,,,1550,27.50,0
    """

    // MARK: - Signature

    @Test func bannerWithoutVersionNumberIsConfirmed() {
        #expect(PHD2LogSignature.classify(Data(Self.log.utf8)) == .confirmed)
    }

    @Test func unrelatedPHD2PrefixIsNotABanner() {
        // Only a space or a comma may follow "PHD2 version"; anything else is not
        // the banner, and with no section markers the file is not a guide log.
        let text = "PHD2 versionless notes\nnothing else here\n"
        #expect(PHD2LogSignature.classify(Data(text.utf8)) == .notPHD2)
    }

    /// The ASIAir saves an Autorun log beside each guide log. Opening it should
    /// name what it is rather than report a generic "not a PHD2 log". Line
    /// shapes follow a real Autorun log (October 2026); values are synthetic.
    @Test func autorunLogIsRecognized() {
        let autorun = """
        Log enabled at 2026/10/16 19:28:02
        2026/10/16 19:28:02 [Autorun|Begin] M 31 Start
        2026/10/16 19:28:03 Target RA:0h42m44s DEC:+41°16'9"
        2026/10/16 19:28:03 Shooting 20 light frames, exposure 120.0s Bin1
        2026/10/16 19:28:09 [Guide] Start Guiding
        """
        #expect(PHD2LogSignature.classify(Data(autorun.utf8)) == .asiAirAutorunLog)
    }

    @Test func guideLogMentioningAutorunIsStillAGuideLog() {
        // PHD2 markers win: a bannerless guide-log fragment whose INFO text
        // happens to contain the Autorun marker is still a likely guide log.
        let text = """
        Guiding Begins at 2026-10-16 19:32:59
        INFO: [Autorun|Begin] noted
        """
        #expect(PHD2LogSignature.classify(Data(text.utf8)) == .likely)
    }

    // MARK: - Parser

    @Test func parsesBannerWithEmptyPHD2Version() {
        let log = GuideLogParser.parse(Self.log)
        #expect(log.phdVersion == "")
        #expect(log.logVersion.hasPrefix("2.5"))
    }

    @Test func parsesCalibrationAndBothSessions() {
        let log = GuideLogParser.parse(Self.log)
        #expect(log.calibrations.count == 1)
        #expect(log.guideSessions.count == 2)
        // The last session has no "Guiding Ends" line; end of file closes it.
        #expect(log.guideSessions.map(\.entries.count) == [2, 3])
        #expect(log.guideSessions.allSatisfy { $0.malformedFieldCount == 0 })
    }

    // MARK: - Pointing line without RA

    @Test func pointingLineWithoutRAStillYieldsDecHourAngleAndPierSide() throws {
        let sessions = GuideLogParser.parse(Self.log).guideSessions
        let first = sessions[0].headerProperties
        #expect(first.raHours == nil)
        #expect(try #require(first.decDegrees) == 15.6)
        #expect(try #require(first.hourAngleHours) == 0.19)
        #expect(first.pierSide == "West")
        #expect(first.hasPointingFix == false)

        let second = sessions[1].headerProperties
        #expect(try #require(second.decDegrees) == 31.2)
        #expect(try #require(second.hourAngleHours) == -0.93)
        #expect(second.pierSide == "East")
    }

    @Test func pointingLineWithRAStillParsesAllFields() throws {
        let props = SessionHeaderProperties(rawHeader: [
            "RA = 12.64 hr, Dec = 13.0 deg, Hour angle = -2.36 hr, Pier side = West, Rotator pos = N/A, Alt = 52.4 deg, Az = 112.3 deg",
        ])
        #expect(try #require(props.raHours) == 12.64)
        #expect(try #require(props.decDegrees) == 13.0)
        #expect(try #require(props.hourAngleHours) == -2.36)
        #expect(props.pierSide == "West")
        #expect(props.hasPointingFix)
    }

    @Test func otherDecFieldsAreNotMistakenForPointing() {
        // "Norm rates ... Dec = 10.2\"/s" and "Cal Dec = 15.6" carry a Dec value
        // but are not the pointing line.
        let props = SessionHeaderProperties(rawHeader: [
            #"Norm rates RA = 8.3"/s @ dec 0, Dec = 10.2"/s; ortho.err. = 12.2 deg"#,
            "RA Guide Speed = 13.5 a-s/s, Dec Guide Speed = 13.5 a-s/s, Cal Dec = 15.6, Last Cal Issue = None",
        ])
        #expect(props.decDegrees == nil)
        #expect(props.raHours == nil)
        #expect(props.pierSide == nil)
    }

    // MARK: - Rig identity

    /// The ASIAir leaves `Equipment Profile =` blank, so the rig key comes from
    /// the guide train. The synthetic log's last session has no Camera line, so
    /// this also covers falling back to an earlier session.
    @Test func blankProfileBuildsKeyFromGuideTrain() throws {
        let log = GuideLogParser.parse(Self.log)
        let key = try #require(RigIdentity.key(for: log))
        #expect(key == "ASIAir · ZWO ASI120MC-S · 120 mm · EQMod Mount")
        #expect(RigIdentity.isASIAirKey(key))
        #expect(RigIdentity.key(for: log.guideSessions[1]) == nil)
    }

    @Test func namedProfileIsTheKey() {
        var session = GuideSession()
        session.rawHeader = [
            "Equipment Profile = Edge-10m",
            "Camera = ZWO ASI174MM Mini, gain = 400, pixel size = 5.9 um",
            "Pixel scale = 0.62 arc-sec/px, Binning = 1, Focal length = 1960 mm",
        ]
        session.mount.name = "10Micron"
        #expect(RigIdentity.key(for: session) == "Edge-10m")
        #expect(!RigIdentity.isASIAirKey("Edge-10m"))
    }

    @Test func blankProfileWithoutGuideTrainHasNoKey() {
        var session = GuideSession()
        session.rawHeader = ["Equipment Profile =", "Exposure = 1500 ms"]
        #expect(RigIdentity.key(for: session) == nil)
    }

    /// Codex review: a corrupt focal length too large for Int trapped when the
    /// key was formatted. It must read as missing instead.
    @Test(arguments: [
        "9223372036854775808",
        String(repeating: "9", count: 400),
        "100001",
    ])
    func implausibleFocalLengthIsTreatedAsMissing(_ value: String) {
        var session = GuideSession()
        session.rawHeader = [
            "Equipment Profile =",
            "Camera = ZWO ASI120MC-S, pixel size = 3.8 um",
            "Pixel scale = 6.45 arc-sec/px, Binning = 1, Focal length = \(value) mm",
        ]
        session.mount.name = "EQMod Mount"
        #expect(RigIdentity.key(for: session) == nil)
    }

    @Test func missingProfileLineHasNoKey() {
        // Only the blank line ASIAir writes triggers the guide-train key; a
        // header with no profile line at all stays unmatched, as before.
        var session = GuideSession()
        session.rawHeader = [
            "Camera = ZWO ASI120MC-S, pixel size = 3.8 um",
            "Pixel scale = 6.45 arc-sec/px, Binning = 1, Focal length = 120 mm",
        ]
        #expect(RigIdentity.key(for: session) == nil)
    }

    @Test func differentMountIsADifferentRig() throws {
        let iOptron = Self.log.replacingOccurrences(of: "EQMod Mount", with: "iOptron CEM26/GEM28/HEM27")
        let a = try #require(RigIdentity.key(for: GuideLogParser.parse(Self.log)))
        let b = try #require(RigIdentity.key(for: GuideLogParser.parse(iOptron)))
        #expect(a != b)
        #expect(b == "ASIAir · ZWO ASI120MC-S · 120 mm · iOptron CEM26/GEM28/HEM27")
    }

    // MARK: - Bulk import

    /// The reported bug: every ASIAir log failed bulk import with "no Equipment
    /// Profile line". Two nights from one guide train should import into one
    /// auto-created rig.
    @MainActor
    @Test func bulkImportIngestsASIAirLogsIntoOneRig() async throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("ASIAirImport-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }

        let secondNight = Self.log.replacingOccurrences(of: "2026-10-16", with: "2026-10-17")
        try Self.log.write(to: folder.appendingPathComponent("PHD2_GuideLog_2026-10-16_193046.txt"),
                           atomically: true, encoding: .utf8)
        try secondNight.write(to: folder.appendingPathComponent("PHD2_GuideLog_2026-10-17_193046.txt"),
                              atomically: true, encoding: .utf8)

        let library = try EphemerisLibrary(inMemory: true)
        let rigStore = RigProfileStore(container: library.container,
                                       legacyJSONDirectory: folder.appendingPathComponent("Profiles", isDirectory: true))
        let importer = LibraryBulkImporter(library: library, rigStore: rigStore)
        importer.importFolder(folder)

        var summary: LibraryBulkImporter.Summary?
        for _ in 0..<200 {
            if case .completed(let s) = importer.status { summary = s; break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let result = try #require(summary, "Bulk import did not finish")
        #expect(result.errors.isEmpty, "\(result.errors)")
        #expect(result.imported == 2)
        #expect(result.autoCreatedRigs == ["ASIAir · ZWO ASI120MC-S · 120 mm · EQMod Mount"])
        #expect(rigStore.profiles.count == 1)
        #expect(rigStore.profiles.first?.guideFocalLength == 120)
    }
}
