//
//  CSVExporter.swift
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

/// CSV serializers for the data this app already computes.
enum CSVExporter {

    // MARK: - Session stats (one row)

    static func sessionStatsCSV(
        _ session: GuideSession,
        manualExclusionRanges: [ClosedRange<Double>] = []
    ) -> String {
        let stats = SessionStatsCalculator.calculate(session, manualExclusionRanges: manualExclusionRanges)
        let scale = session.pixelScale
        let header = [
            "Started", "Duration_s", "Frames", "Included", "Excluded",
            "RMS_RA_px", "RMS_RA_arcsec",
            "RMS_Dec_px", "RMS_Dec_arcsec",
            "RMS_Total_px", "RMS_Total_arcsec",
            "Peak_RA_px", "Peak_Dec_px",
            "Drift_RA_px_per_min", "Drift_Dec_px_per_min",
            "Polar_Align_arcmin",
            "Pixel_scale_arcsec_per_px",
            "Declination_deg"
        ].joined(separator: ",")

        let started = session.startedAt.map { Self.iso.string(from: $0) } ?? ""
        let row = [
            quote(started),
            String(format: "%.3f", session.duration),
            "\(session.frameCount)",
            "\(stats.includedFrames)",
            "\(stats.excludedFrames)",
            String(format: "%.4f", stats.rmsRA),
            String(format: "%.4f", stats.rmsRA * scale),
            String(format: "%.4f", stats.rmsDec),
            String(format: "%.4f", stats.rmsDec * scale),
            String(format: "%.4f", stats.rmsTotal),
            String(format: "%.4f", stats.rmsTotal * scale),
            String(format: "%.4f", stats.peakRA),
            String(format: "%.4f", stats.peakDec),
            String(format: "%.4f", stats.driftRA),
            String(format: "%.4f", stats.driftDec),
            stats.polarAlignErrorArcmin.map { String(format: "%.3f", $0) } ?? "",
            String(format: "%.4f", scale),
            String(format: "%.3f", session.declination * 180 / .pi)
        ].joined(separator: ",")
        return header + "\n" + row + "\n"
    }

    // MARK: - Frame data (one row per guide entry)

    static func frameDataCSV(_ session: GuideSession) -> String {
        let header = [
            "Frame", "Time_s", "Device",
            "dx", "dy",
            "RA_RawDist", "Dec_RawDist",
            "RA_GuideDist", "Dec_GuideDist",
            "RA_Duration_signed", "Dec_Duration_signed",
            "X_Step", "Y_Step",
            "Star_Mass", "SNR",
            "Error_Code", "Included",
            "Info"
        ].joined(separator: ",")

        // Skip boundary sentinels from `GuideSessionMerger`. Their NaN-valued
        // numeric fields would otherwise serialise as the literal string "nan",
        // which breaks spreadsheet-portable numeric column parsing.
        let realEntries = session.entries.filter { !$0.raRawDistance.isNaN }
        var rows: [String] = []
        rows.reserveCapacity(realEntries.count)
        for e in realEntries {
            let row = [
                "\(e.frame)",
                String(format: "%.3f", e.time),
                e.deviceKind == .ao ? "AO" : "Mount",
                String(format: "%.4f", e.dx),
                String(format: "%.4f", e.dy),
                String(format: "%.4f", e.raRawDistance),
                String(format: "%.4f", e.decRawDistance),
                String(format: "%.4f", e.raGuideDistance),
                String(format: "%.4f", e.decGuideDistance),
                "\(e.raDuration)",
                "\(e.decDuration)",
                e.xStep.map(String.init) ?? "",
                e.yStep.map(String.init) ?? "",
                "\(e.starMass)",
                String(format: "%.3f", e.snr),
                "\(e.errorCode)",
                e.included ? "1" : "0",
                quote(e.info ?? "")
            ].joined(separator: ",")
            rows.append(row)
        }
        return header + "\n" + rows.joined(separator: "\n") + "\n"
    }

    // MARK: - Aggregate (one row per guide session)

    static func aggregateCSV(_ log: GuideLog) -> String {
        let header = [
            "Index", "Started", "Duration_s",
            "Included", "Excluded",
            "RMS_RA_arcsec", "RMS_Dec_arcsec", "RMS_Total_arcsec",
            "Peak_RA_arcsec", "Peak_Dec_arcsec",
            "Drift_RA_arcsec_per_min", "Drift_Dec_arcsec_per_min",
            "Polar_Align_arcmin",
            "Pixel_scale_arcsec_per_px"
        ].joined(separator: ",")

        var rows: [String] = []
        for (i, s) in log.guideSessions.enumerated() {
            let stats = SessionStatsCalculator.calculate(s)
            let scale = s.pixelScale
            let row = [
                "\(i)",
                quote(s.startedAt.map { Self.iso.string(from: $0) } ?? ""),
                String(format: "%.3f", s.duration),
                "\(stats.includedFrames)",
                "\(stats.excludedFrames)",
                String(format: "%.4f", stats.rmsRA * scale),
                String(format: "%.4f", stats.rmsDec * scale),
                String(format: "%.4f", stats.rmsTotal * scale),
                String(format: "%.4f", stats.peakRA * scale),
                String(format: "%.4f", stats.peakDec * scale),
                String(format: "%.4f", stats.driftRA * scale),
                String(format: "%.4f", stats.driftDec * scale),
                stats.polarAlignErrorArcmin.map { String(format: "%.3f", $0) } ?? "",
                String(format: "%.4f", scale)
            ].joined(separator: ",")
            rows.append(row)
        }
        return header + "\n" + rows.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        return f
    }()

    /// Wrap a string in double quotes, escaping any embedded quotes per RFC 4180.
    private static func quote(_ s: String) -> String {
        if s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
