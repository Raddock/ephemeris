import XCTest
@testable import Ephemeris

@MainActor
final class RigProfileStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EphemerisStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    func test_emptyStore_returnsNoProfiles() {
        let store = RigProfileStore(directory: tempDir)
        XCTAssertEqual(store.profiles.count, 0)
    }

    func test_saveAndReload_roundTripsProfile() throws {
        let store1 = RigProfileStore(directory: tempDir)
        var profile = RigProfile(currentName: "Edge-10m")
        profile.imagingFocalLength = 1960
        profile.imagingPixelSize = 5.9
        profile.mountClass = .encoderBasedPremium
        profile.hasHighPrecisionEncoders = true
        try store1.save(profile)
        XCTAssertEqual(store1.profiles.count, 1)

        let store2 = RigProfileStore(directory: tempDir)
        XCTAssertEqual(store2.profiles.count, 1)
        let reloaded = store2.profiles.first
        XCTAssertEqual(reloaded?.currentName, "Edge-10m")
        XCTAssertEqual(reloaded?.imagingFocalLength, 1960)
        XCTAssertEqual(reloaded?.mountClass, .encoderBasedPremium)
        XCTAssertTrue(reloaded?.hasHighPrecisionEncoders == true)
    }

    func test_save_updatesExistingProfileById() throws {
        let store = RigProfileStore(directory: tempDir)
        var profile = RigProfile(currentName: "Original")
        try store.save(profile)
        profile.currentName = "Renamed"
        try store.save(profile)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.currentName, "Renamed")
    }

    func test_delete_removesFile() throws {
        let store = RigProfileStore(directory: tempDir)
        let profile = RigProfile(currentName: "Will Delete")
        try store.save(profile)
        XCTAssertEqual(store.profiles.count, 1)
        try store.delete(profile)
        XCTAssertEqual(store.profiles.count, 0)

        let reload = RigProfileStore(directory: tempDir)
        XCTAssertEqual(reload.profiles.count, 0)
    }

    func test_matchingPHD2Name_findsCurrentOrHistorical() throws {
        let store = RigProfileStore(directory: tempDir)
        var profile = RigProfile(currentName: "Edge-10m")
        try store.save(profile)
        XCTAssertNotNil(store.profile(matchingPHD2Name: "Edge-10m"))
        XCTAssertNil(store.profile(matchingPHD2Name: "Nonexistent"))
        profile.repairPhd2Name(to: "Edge HD")
        try store.save(profile)
        XCTAssertNotNil(store.profile(matchingPHD2Name: "Edge HD"))         // current
        XCTAssertNotNil(store.profile(matchingPHD2Name: "Edge-10m"))         // historical
    }

    func test_modifiedAtBumpedOnSave() throws {
        let store = RigProfileStore(directory: tempDir)
        let originalDate = Date(timeIntervalSince1970: 0)
        var profile = RigProfile(currentName: "T", createdAt: originalDate, modifiedAt: originalDate)
        try store.save(profile)
        XCTAssertGreaterThan(store.profiles.first!.modifiedAt, originalDate)
    }
}
