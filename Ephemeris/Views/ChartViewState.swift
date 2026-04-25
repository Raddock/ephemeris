//
//  ChartViewState.swift
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
import SwiftUI

@Observable
@MainActor
final class ChartViewState {
    enum Units: String, CaseIterable, Identifiable {
        case pixels, arcsec
        var id: Self { self }
        var label: String {
            switch self {
            case .pixels: return "Pixels"
            case .arcsec: return "Arc-sec"
            }
        }
    }

    enum AxisMode: String, CaseIterable, Identifiable {
        case raDec, dxDy
        var id: Self { self }
        var label: String {
            switch self {
            case .raDec: return "RA / Dec"
            case .dxDy:  return "dx / dy"
            }
        }
    }

    enum DragMode: String, CaseIterable, Identifiable {
        case zoom, exclude
        var id: Self { self }
        var label: String {
            switch self {
            case .zoom:    return "Zoom"
            case .exclude: return "Exclude"
            }
        }
        var systemImage: String {
            switch self {
            case .zoom:    return "magnifyingglass"
            case .exclude: return "rectangle.dashed"
            }
        }
    }

    /// Y-axis range setting for the main guide chart. `.auto` uses 10% padding
    /// around the largest visible-domain magnitude; `.fixedArcsec` clamps to a
    /// symmetric ± range expressed in arcseconds (converted to pixels when the
    /// user has selected `Pixels` units).
    enum YScale: Equatable, Hashable, Sendable {
        case auto
        case fixedArcsec(Double)

        var label: String {
            switch self {
            case .auto: return "Auto"
            case .fixedArcsec(let n):
                if n < 1 { return String(format: "±%.1f\"", n) }
                return String(format: "±%.0f\"", n)
            }
        }
    }

    var units: Units {
        didSet { Self.defaults.set(units.rawValue, forKey: Keys.units) }
    }
    var axisMode: AxisMode {
        didSet { Self.defaults.set(axisMode.rawValue, forKey: Keys.axisMode) }
    }
    var dragMode: DragMode {
        didSet { Self.defaults.set(dragMode.rawValue, forKey: Keys.dragMode) }
    }
    var yScale: YScale {
        didSet {
            switch yScale {
            case .auto: Self.defaults.set(0.0, forKey: Keys.yScale)
            case .fixedArcsec(let v): Self.defaults.set(v, forKey: Keys.yScale)
            }
        }
    }
    var showRA: Bool {
        didSet { Self.defaults.set(showRA, forKey: Keys.showRA) }
    }
    var showDec: Bool {
        didSet { Self.defaults.set(showDec, forKey: Keys.showDec) }
    }
    var showCorrections: Bool {
        didSet { Self.defaults.set(showCorrections, forKey: Keys.showCorrections) }
    }
    var showStarMass: Bool {
        didSet { Self.defaults.set(showStarMass, forKey: Keys.showStarMass) }
    }
    var showSNR: Bool {
        didSet { Self.defaults.set(showSNR, forKey: Keys.showSNR) }
    }
    var showEvents: Bool {
        didSet { Self.defaults.set(showEvents, forKey: Keys.showEvents) }
    }
    var showLimits: Bool {
        didSet { Self.defaults.set(showLimits, forKey: Keys.showLimits) }
    }
    var showGrid: Bool {
        didSet { Self.defaults.set(showGrid, forKey: Keys.showGrid) }
    }
    var showScatter: Bool {
        didSet { Self.defaults.set(showScatter, forKey: Keys.showScatter) }
    }
    var showHoverCard: Bool {
        didSet { Self.defaults.set(showHoverCard, forKey: Keys.showHoverCard) }
    }

    init() {
        let d = Self.defaults
        units = d.string(forKey: Keys.units).flatMap(Units.init(rawValue:)) ?? .arcsec
        axisMode = d.string(forKey: Keys.axisMode).flatMap(AxisMode.init(rawValue:)) ?? .raDec
        dragMode = d.string(forKey: Keys.dragMode).flatMap(DragMode.init(rawValue:)) ?? .zoom
        let y = d.double(forKey: Keys.yScale)
        yScale = y > 0 ? .fixedArcsec(y) : .auto
        showRA = d.object(forKey: Keys.showRA) as? Bool ?? true
        showDec = d.object(forKey: Keys.showDec) as? Bool ?? true
        showCorrections = d.object(forKey: Keys.showCorrections) as? Bool ?? true
        showStarMass = d.object(forKey: Keys.showStarMass) as? Bool ?? false
        showSNR = d.object(forKey: Keys.showSNR) as? Bool ?? false
        showEvents = d.object(forKey: Keys.showEvents) as? Bool ?? true
        showLimits = d.object(forKey: Keys.showLimits) as? Bool ?? false
        showGrid = d.object(forKey: Keys.showGrid) as? Bool ?? true
        showScatter = d.object(forKey: Keys.showScatter) as? Bool ?? true
        showHoverCard = d.object(forKey: Keys.showHoverCard) as? Bool ?? true
    }

    private static let defaults = UserDefaults.standard

    private enum Keys {
        static let units = "chart.units"
        static let axisMode = "chart.axisMode"
        static let dragMode = "chart.dragMode"
        static let yScale = "chart.yScaleArcsec"
        static let showRA = "chart.showRA"
        static let showDec = "chart.showDec"
        static let showCorrections = "chart.showCorrections"
        static let showStarMass = "chart.showStarMass"
        static let showSNR = "chart.showSNR"
        static let showEvents = "chart.showEvents"
        static let showLimits = "chart.showLimits"
        static let showGrid = "chart.showGrid"
        static let showScatter = "chart.showScatter"
        static let showHoverCard = "chart.showHoverCard"
    }
}
