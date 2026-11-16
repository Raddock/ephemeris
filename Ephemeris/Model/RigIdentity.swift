//
//  RigIdentity.swift
//  Ephemeris
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

/// The key that matches a guide log to a `RigProfile` (stored as the rig's
/// `currentName`). Every caller that needs "which rig is this log from?" goes
/// through here, so the document window, the bulk importer, and the inspector
/// can't disagree.
///
/// PHD2 logs carry the key directly: the `Equipment Profile = X` line. ZWO's
/// ASIAir writes that line blank, so for those logs the key is built from the
/// guide train the header does record (camera, guide focal length, mount),
/// which is what a PHD2 profile stands for. The result is prefixed so the UI
/// can tell a built key from a real profile name.
nonisolated enum RigIdentity {

    /// Prefix on keys built from an ASIAir header. Persisted as part of the
    /// rig's `currentName`, so changing it orphans existing ASIAir rigs.
    static let asiAirPrefix = "ASIAir · "

    /// True when `key` was built from an ASIAir header rather than read from
    /// a PHD2 `Equipment Profile` line.
    static func isASIAirKey(_ key: String) -> Bool {
        key.hasPrefix(asiAirPrefix)
    }

    /// The rig key for a whole log: the last guide session that yields one,
    /// matching PHD2's habit of writing the active profile into every header.
    static func key(for log: GuideLog) -> String? {
        for session in log.guideSessions.reversed() {
            if let key = key(for: session) { return key }
        }
        return nil
    }

    /// The rig key for one guide session, or nil when the header names no
    /// profile and lacks the guide-train fields to build one.
    static func key(for session: GuideSession) -> String? {
        switch profileLine(in: session.rawHeader) {
        case .named(let name):
            return name
        case .blank:
            return asiAirKey(header: session.rawHeader, mountName: session.mount.name)
        case .absent:
            return nil
        }
    }

    // MARK: - Internals

    private enum ProfileLine {
        case named(String)
        /// The line is present with no value: what ASIAir writes.
        case blank
        case absent
    }

    private static func profileLine(in header: [String]) -> ProfileLine {
        for line in header {
            guard let range = line.range(of: "Equipment Profile =") else { continue }
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? .blank : .named(value)
        }
        return .absent
    }

    /// "ASIAir · ZWO ASI174MM Mini · 600 mm · ZWO000". Camera and focal length
    /// are required; the mount is included when named, so one guide scope moved
    /// between mounts reads as two rigs (the recommender's mount class differs).
    private static func asiAirKey(header: [String], mountName: String) -> String? {
        var camera: String?
        var focalLength: Double?
        for line in header {
            if camera == nil, line.hasPrefix("Camera = ") {
                let value = line.dropFirst("Camera = ".count)
                let name = value.prefix { $0 != "," }.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { camera = name }
            }
            if focalLength == nil, let range = line.range(of: "Focal length = ") {
                let digits = line[range.upperBound...].prefix { $0.isNumber || $0 == "." }
                if let mm = Double(digits), mm > 0 { focalLength = mm }
            }
        }
        guard let camera, let focalLength else { return nil }

        let mm = focalLength.rounded() == focalLength
            ? String(Int(focalLength))
            : String(format: "%.1f", focalLength)
        var parts = [camera, "\(mm) mm"]
        let mount = mountName.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        if !mount.isEmpty { parts.append(mount) }
        return asiAirPrefix + parts.joined(separator: " · ")
    }
}
