import XCTest
import SwiftData
@testable import Ephemeris

/// Tests for the SwiftData-backed RigProfileStore (single owner of rig-profile
/// persistence) and the one-time import of the retired JSON sidecar.
@MainActor
final class RigProfileStoreTests: XCTestCase {
    var library: EphemerisLibrary!
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        library = try EphemerisLibrary(inMemory: true)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EphemerisStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        library = nil
        try await super.tearDown()
    }

    /// A store whose legacy-JSON directory points at a scratch folder so tests
    /// never touch the real Application Support location.
    private func makeStore() -> RigProfileStore {
        RigProfileStore(container: library.container,
                        legacyJSONDirectory: tempDir.appendingPathComponent("Profiles", isDirectory: true))
    }

    func test_emptyStore_returnsNoProfiles() {
        XCTAssertEqual(makeStore().profiles.count, 0)
    }

    func test_saveAndReload_roundTripsProfile() throws {
        let store1 = makeStore()
        var profile = RigProfile(currentName: "Edge-10m")
        profile.imagingFocalLength = 1960
        profile.imagingPixelSize = 5.9
        profile.mountClass = .encoderBasedPremium
        profile.hasHighPrecisionEncoders = true
        try store1.save(profile)
        XCTAssertEqual(store1.profiles.count, 1)

        // A second store over the same container sees the same entity.
        let store2 = makeStore()
        XCTAssertEqual(store2.profiles.count, 1)
        let reloaded = store2.profiles.first
        XCTAssertEqual(reloaded?.currentName, "Edge-10m")
        XCTAssertEqual(reloaded?.imagingFocalLength, 1960)
        XCTAssertEqual(reloaded?.mountClass, .encoderBasedPremium)
        XCTAssertTrue(reloaded?.hasHighPrecisionEncoders == true)
    }

    func test_save_updatesExistingProfileById() throws {
        let store = makeStore()
        var profile = RigProfile(currentName: "Original")
        try store.save(profile)
        profile.currentName = "Renamed"
        try store.save(profile)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.currentName, "Renamed")
    }

    func test_delete_removesEntity() throws {
        let store = makeStore()
        let profile = RigProfile(currentName: "Will Delete")
        try store.save(profile)
        XCTAssertEqual(store.profiles.count, 1)
        try store.delete(profile)
        XCTAssertEqual(store.profiles.count, 0)

        let reload = makeStore()
        XCTAssertEqual(reload.profiles.count, 0)
    }

    func test_delete_cascadesNightRecords() throws {
        let store = makeStore()
        let profile = RigProfile(currentName: "Cascade Rig")
        try store.save(profile)

        // Attach a night record to the rig entity, then delete the rig.
        let context = library.container.mainContext
        let pid = profile.id
        let rigEntity = try XCTUnwrap(try context.fetch(
            FetchDescriptor<RigProfileEntity>(predicate: #Predicate { $0.id == pid })
        ).first)
        let night = NightRecordEntity()
        night.rigProfile = rigEntity
        context.insert(night)
        try context.save()

        try store.delete(profile)

        let nights = try context.fetch(FetchDescriptor<NightRecordEntity>())
        XCTAssertEqual(nights.count, 0, "deleting a rig must cascade its night records")
    }

    func test_matchingPHD2Name_findsCurrentOrHistorical() throws {
        let store = makeStore()
        var profile = RigProfile(currentName: "Edge-10m")
        try store.save(profile)
        XCTAssertNotNil(store.profile(matchingPHD2Name: "Edge-10m"))
        XCTAssertNil(store.profile(matchingPHD2Name: "Nonexistent"))
        profile.repairPhd2Name(to: "Edge HD")
        try store.save(profile)
        XCTAssertNotNil(store.profile(matchingPHD2Name: "Edge HD"))          // current
        XCTAssertNotNil(store.profile(matchingPHD2Name: "Edge-10m"))         // historical
    }

    func test_modifiedAtBumpedOnSave() throws {
        let store = makeStore()
        let originalDate = Date(timeIntervalSince1970: 0)
        let profile = RigProfile(currentName: "T", createdAt: originalDate, modifiedAt: originalDate)
        try store.save(profile)
        XCTAssertGreaterThan(store.profiles.first!.modifiedAt, originalDate)
    }

    // MARK: - Legacy JSON sidecar migration

    func test_legacyJSONProfiles_importOnceAndParkTheFolder() throws {
        let legacyDir = tempDir.appendingPathComponent("Profiles", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        var legacy = RigProfile(currentName: "From JSON")
        legacy.imagingFocalLength = 530
        legacy.imagingPixelSize = 3.76
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(
            to: legacyDir.appendingPathComponent("\(legacy.id.uuidString).json"))

        let store = RigProfileStore(container: library.container, legacyJSONDirectory: legacyDir)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.currentName, "From JSON")
        XCTAssertEqual(store.profiles.first?.imagingFocalLength, 530)

        // The folder is parked so a later launch can't re-import stale JSON
        // over newer SwiftData edits.
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDir.path))
        let backup = tempDir.appendingPathComponent("Profiles.migrated-backup", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))

        // Second store: no legacy folder left, entity is the source of truth.
        var edited = try XCTUnwrap(store.profiles.first)
        edited.currentName = "Edited After Migration"
        try store.save(edited)
        let store2 = RigProfileStore(container: library.container, legacyJSONDirectory: legacyDir)
        XCTAssertEqual(store2.profiles.first?.currentName, "Edited After Migration")
    }

    func test_missingContainer_reportsUnavailable() {
        let store = RigProfileStore(container: nil,
                                    legacyJSONDirectory: tempDir.appendingPathComponent("Profiles"))
        XCTAssertEqual(store.profiles.count, 0)
        XCTAssertThrowsError(try store.save(RigProfile(currentName: "X")))
    }
}
