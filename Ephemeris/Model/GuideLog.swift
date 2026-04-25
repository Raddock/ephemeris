//
//  GuideLog.swift
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

struct GuideLog: Sendable {
    var phdVersion: String = ""
    var logVersion: String = ""
    var sections: [SectionRef] = []
    var guideSessions: [GuideSession] = []
    var calibrations: [Calibration] = []

    enum SectionRef: Sendable, Hashable {
        case summary
        case guide(Int)
        case calibration(Int)
    }

    var isEmpty: Bool { sections.isEmpty }
}

struct GuideDevice: Sendable {
    nonisolated enum Kind: Sendable, Equatable { case mount, ao }
    var kind: Kind
    var name: String = ""
    var xAngle: Double = 0
    var xRate: Double = 1.0
    var yAngle: Double = .pi / 2
    var yRate: Double = 1.0
    var maxRADuration: Int? = nil
    var maxDecDuration: Int? = nil
    var guidingEnabled: Bool = false
    var minMoveX: Double? = nil
    var minMoveY: Double? = nil
    var xGuideAlgorithm: String? = nil
    var yGuideAlgorithm: String? = nil
}
