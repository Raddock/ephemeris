//
//  SessionStats.swift
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

/// Summary statistics for a guiding session.
///
/// All distance/peak values are in pixels (the raw signal). The polar-alignment
/// error is in arcminutes since it's already scale- and declination-corrected.
nonisolated struct SessionStats: Sendable, Equatable {
    var includedFrames: Int = 0
    var excludedFrames: Int = 0

    /// Standard deviation of `raRawDistance` across included frames, in pixels.
    var rmsRA: Double = 0
    /// Standard deviation of `decRawDistance` across included frames, in pixels.
    var rmsDec: Double = 0
    /// `sqrt(rmsRA² + rmsDec²)`, in pixels.
    var rmsTotal: Double = 0

    /// Maximum absolute deviation from the mean, in pixels.
    var peakRA: Double = 0
    var peakDec: Double = 0

    /// Linear-regression drift in pixels per minute.
    var driftRA: Double = 0
    var driftDec: Double = 0

    /// König-method polar-alignment error in arcminutes.
    /// `nil` when target declination is within 5° of the celestial pole
    /// (cos(δ) too small for the approximation).
    var polarAlignErrorArcmin: Double? = nil

    static let empty = SessionStats()
}

extension SessionStats {
    /// Convert a pixel value to the requested display units.
    static func display(_ valuePx: Double, as units: ChartViewState.Units, pixelScale: Double) -> Double {
        switch units {
        case .pixels: return valuePx
        case .arcsec: return valuePx * pixelScale
        }
    }
}
