import Foundation
import Observation

/// JSON-sidecar persistence for rig profiles. v2.0 Phase 1 storage.
/// Phase 3 migrates this to SwiftData; this layer disappears at that point.
///
/// Files live in `~/Library/Application Support/Ephemeris/Profiles/`, one JSON file
/// per profile. Filename = `{uuid}.json`. The directory is created on first write.
@Observable
@MainActor
final class RigProfileStore {
    private(set) var profiles: [RigProfile] = []

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
        load()
    }

    static func defaultDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Ephemeris", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
    }

    /// Reload all profiles from disk. Called automatically on init.
    func load() {
        ensureDirectoryExists()
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            profiles = []
            return
        }
        var loaded: [RigProfile] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let profile = try? decoder.decode(RigProfile.self, from: data)
            else { continue }
            loaded.append(profile)
        }
        profiles = loaded.sorted { $0.currentName.localizedCompare($1.currentName) == .orderedAscending }
    }

    /// Insert or update a profile. The `modifiedAt` timestamp is bumped to now.
    func save(_ profile: RigProfile) throws {
        ensureDirectoryExists()
        var p = profile
        p.modifiedAt = .now
        let data = try encoder.encode(p)
        try data.write(to: fileURL(for: p), options: .atomic)
        if let idx = profiles.firstIndex(where: { $0.id == p.id }) {
            profiles[idx] = p
        } else {
            profiles.append(p)
        }
        profiles.sort { $0.currentName.localizedCompare($1.currentName) == .orderedAscending }
    }

    func delete(_ profile: RigProfile) throws {
        let url = fileURL(for: profile)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        profiles.removeAll { $0.id == profile.id }
    }

    /// Find a profile that matches the given PHD2 profile name (current or historical).
    /// Per §12 Q1 of the design doc: this is auto-association on name match.
    func profile(matchingPHD2Name name: String) -> RigProfile? {
        profiles.first { $0.matches(profileName: name) }
    }

    private func fileURL(for profile: RigProfile) -> URL {
        directory.appendingPathComponent("\(profile.id.uuidString).json")
    }

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
