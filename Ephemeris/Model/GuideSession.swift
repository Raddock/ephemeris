//
//  GuideSession.swift
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

struct GuideSession: Sendable, Identifiable {
    let id = UUID()
    var startedAt: Date?
    var rawHeader: [String] = []
    var mount: GuideDevice = GuideDevice(kind: .mount)
    var ao: GuideDevice? = nil
    var pixelScale: Double = 1.0
    var declination: Double = 0
    var entries: [GuideEntry] = []
    var infos: [InfoEntry] = []

    nonisolated var duration: Double { entries.last?.time ?? 0 }
    /// Count of real frames only — boundary sentinels inserted by
    /// `GuideSessionMerger` (NaN-valued, non-included) are excluded so the
    /// number matches what a user would say came from PHD2.
    var frameCount: Int {
        entries.lazy.filter { !$0.raRawDistance.isNaN }.count
    }
}

struct GuideEntry: Sendable, Identifiable {
    var id: Int { frame }
    var frame: Int
    var time: Double
    var deviceKind: GuideDevice.Kind
    var dx: Double
    var dy: Double
    var raRawDistance: Double
    var decRawDistance: Double
    var raGuideDistance: Double
    var decGuideDistance: Double
    var raDuration: Int
    var decDuration: Int
    var xStep: Int?
    var yStep: Int?
    var starMass: Int
    var snr: Double
    var errorCode: Int
    var included: Bool
    var guiding: Bool
    var info: String?
}

struct InfoEntry: Sendable, Identifiable {
    let id = UUID()
    var frame: Int
    var text: String
    var repeats: Int = 1
}
