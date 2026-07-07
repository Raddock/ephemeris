//
//  GuideLogParser.swift
//  Ephemeris
//
//  Copyright (C) 2026 Andrew Burwell
//
//  This file derives behavioral logic from logparser.cpp / logparser.h
//  in agalasso/phdlogview, Copyright (C) 2016-2020 Andy Galasso,
//  licensed under GPLv3. Original: https://github.com/agalasso/phdlogview
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

enum GuideLogParser {

    static func parse(_ text: String) -> GuideLog {
        var log = GuideLog()
        var state: State = .skip
        var pendingGuide: GuideSession? = nil
        var pendingCal: Calibration? = nil
        var hdrCursor = HeaderCursorState()

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " \r\n\t"))

            if state == .skip {
                if let v = parseTopVersion(line) {
                    log.phdVersion = v.phd
                    log.logVersion = v.log
                    continue
                }
                if let dt = parseSectionStart(line, prefix: "Guiding Begins at ") {
                    pendingGuide = GuideSession(startedAt: dt)
                    hdrCursor = HeaderCursorState()
                    state = .guidingHeader
                    continue
                }
                if let dt = parseSectionStart(line, prefix: "Calibration Begins at ") {
                    pendingCal = Calibration(startedAt: dt)
                    state = .calibrationHeader
                    continue
                }
                continue
            }

            if state == .guidingHeader {
                if line.hasPrefix("Frame,Time,mount") {
                    state = .guiding
                    continue
                }
                if line.isEmpty || line.hasPrefix("Guiding Ends") {
                    finalizeGuide(&log, &pendingGuide)
                    state = .skip
                    continue
                }
                if var sess = pendingGuide {
                    sess.rawHeader.append(line)
                    HeaderParser.apply(line, to: &sess, cursor: &hdrCursor)
                    pendingGuide = sess
                }
                continue
            }

            if state == .guiding {
                if line.isEmpty || line.hasPrefix("Guiding Ends") {
                    finalizeGuide(&log, &pendingGuide)
                    state = .skip
                    continue
                }
                if let first = line.first, first.isNumber, var sess = pendingGuide {
                    var malformed = 0
                    if let entry = parseGuideRow(line, mountEnabled: sess.mount.guidingEnabled,
                                                 malformedFields: &malformed) {
                        sess.entries.append(entry)
                        if let info = entry.info, !info.isEmpty {
                            sess.infos.append(InfoEntry(frame: entry.frame, text: info))
                        }
                    }
                    sess.malformedFieldCount += malformed
                    pendingGuide = sess
                    continue
                }
                if line.hasPrefix("INFO: "), var sess = pendingGuide {
                    let frame = sess.entries.last?.frame ?? 0
                    let text = String(line.dropFirst("INFO: ".count))
                    if let toggle = parseMountGuidingToggle(text) {
                        sess.mount.guidingEnabled = toggle
                    }
                    sess.infos.append(InfoEntry(frame: frame, text: cleanInfoText(text)))
                    pendingGuide = sess
                    continue
                }
                continue
            }

            if state == .calibrationHeader {
                if line.hasPrefix("Direction,Step,dx,dy") {
                    state = .calibrating
                    continue
                }
                if line.isEmpty || line.hasPrefix("Calibration complete") {
                    finalizeCalibration(&log, &pendingCal)
                    state = .skip
                    continue
                }
                pendingCal?.rawHeader.append(line)
                continue
            }

            if state == .calibrating {
                if line.isEmpty || line.hasPrefix("Calibration complete") {
                    finalizeCalibration(&log, &pendingCal)
                    state = .skip
                    continue
                }
                if let entry = parseCalibrationRow(line, into: &pendingCal) {
                    pendingCal?.entries.append(entry)
                } else {
                    pendingCal?.rawHeader.append(line)
                }
                continue
            }
        }

        // Tail: file ended mid-section.
        if state == .guiding || state == .guidingHeader {
            finalizeGuide(&log, &pendingGuide)
        }
        if state == .calibrating || state == .calibrationHeader {
            finalizeCalibration(&log, &pendingCal)
        }

        for i in log.guideSessions.indices {
            log.guideSessions[i] = NonMonotonicFix.apply(to: log.guideSessions[i])
            log.guideSessions[i].infos = InfoCoalescer.coalesce(log.guideSessions[i].infos)
        }

        return log
    }

    // MARK: - States

    private enum State { case skip, guidingHeader, guiding, calibrationHeader, calibrating }

    // MARK: - Finalization

    private static func finalizeGuide(_ log: inout GuideLog, _ pending: inout GuideSession?) {
        guard let s = pending else { return }
        let idx = log.guideSessions.count
        log.guideSessions.append(s)
        log.sections.append(.guide(idx))
        pending = nil
    }

    private static func finalizeCalibration(_ log: inout GuideLog, _ pending: inout Calibration?) {
        guard var c = pending else { return }
        c.details = CalibrationHeaderParser.parse(c.rawHeader)
        let idx = log.calibrations.count
        log.calibrations.append(c)
        log.sections.append(.calibration(idx))
        pending = nil
    }

    // MARK: - Top of file / section starts

    private static func parseTopVersion(_ line: String) -> (phd: String, log: String)? {
        guard line.hasPrefix("PHD2 version ") else { return nil }
        let rest = line.dropFirst("PHD2 version ".count)
        if let r = rest.range(of: ", Log version ") {
            let phd = String(rest[..<r.lowerBound])
            let log = String(rest[r.upperBound...])
            return (phd, log)
        }
        return (String(rest), "")
    }

    private static func parseSectionStart(_ line: String, prefix: String) -> Date? {
        guard line.hasPrefix(prefix) else { return nil }
        let dateStr = String(line.dropFirst(prefix.count))
        return ISODateParser.parse(dateStr)
    }

    // MARK: - Guide row

    /// Parse one guide row. Fields that are present but unparseable are coerced
    /// to 0 (matching the original phdlogview tolerance) AND counted through
    /// `malformedFields` — a corrupt log must not silently read as perfect
    /// guiding. Empty fields are legitimately zero (PHD2 omits values, e.g. no
    /// correction issued) and are not counted. Rows with fewer than 18 fields
    /// (a truncated final line is normal when PHD2 dies mid-write) are skipped
    /// without counting.
    static func parseGuideRow(_ line: String, mountEnabled: Bool,
                              malformedFields: inout Int) -> GuideEntry? {
        let f = CSVTokenizer.split(line)
        guard f.count >= 18 else { return nil }
        guard let frame = Int(f[0]), let time = Double(f[1]) else {
            malformedFields += 1
            return nil
        }

        func coerceDouble(_ s: String) -> Double {
            if s.isEmpty { return 0 }
            if let v = Double(s) { return v }
            malformedFields += 1
            return 0
        }
        func coerceInt(_ s: String) -> Int {
            if s.isEmpty { return 0 }
            if let v = Int(s) { return v }
            malformedFields += 1
            return 0
        }

        let deviceKind: GuideDevice.Kind = (f[2] == "AO") ? .ao : .mount
        let dx = coerceDouble(f[3])
        let dy = coerceDouble(f[4])
        let raRaw = coerceDouble(f[5])
        let decRaw = coerceDouble(f[6])
        let raGuide = coerceDouble(f[7])
        let decGuide = coerceDouble(f[8])

        var raDur = coerceInt(f[9])
        if f[10] == "W" { raDur = -raDur }
        var decDur = coerceInt(f[11])
        if f[12] == "S" { decDur = -decDur }

        // AO step fields stay nil when empty (the normal non-AO case) or when
        // garbage — but garbage counts as malformed like every other field.
        func coerceOptionalInt(_ s: String) -> Int? {
            if s.isEmpty { return nil }
            if let v = Int(s) { return v }
            malformedFields += 1
            return nil
        }
        let xStep = coerceOptionalInt(f[13])
        let yStep = coerceOptionalInt(f[14])
        if let xs = xStep { raDur = xs }
        if let ys = yStep { decDur = ys }

        let mass = coerceInt(f[15])
        let snr = coerceDouble(f[16])
        let err = coerceInt(f[17])
        let included = (err == 0 || err == 1)
        var info: String? = (f.count > 18) ? f[18] : nil
        if !included, (info?.isEmpty ?? true) { info = "Frame dropped" }

        return GuideEntry(
            frame: frame, time: time, deviceKind: deviceKind,
            dx: dx, dy: dy,
            raRawDistance: raRaw, decRawDistance: decRaw,
            raGuideDistance: raGuide, decGuideDistance: decGuide,
            raDuration: raDur, decDuration: decDur,
            xStep: xStep, yStep: yStep,
            starMass: mass, snr: snr, errorCode: err,
            included: included, guiding: mountEnabled,
            info: (info?.isEmpty == false) ? info : nil
        )
    }

    // MARK: - Calibration row

    private static func parseCalibrationRow(_ line: String, into pending: inout Calibration?) -> CalibrationEntry? {
        let f = CSVTokenizer.split(line)
        guard f.count >= 4, let dir = CalibrationEntry.Direction(token: f[0]) else { return nil }
        if let dev = CalibrationEntry.Direction.device(forToken: f[0]) {
            pending?.device = dev
        }
        let step = Int(f[1]) ?? 0
        let dx = Double(f[2]) ?? 0
        let dy = Double(f[3]) ?? 0
        return CalibrationEntry(direction: dir, step: step, dx: dx, dy: dy)
    }

    // MARK: - INFO helpers

    private static func parseMountGuidingToggle(_ text: String) -> Bool? {
        guard let r = text.range(of: "MountGuidingEnabled = ") else { return nil }
        let suffix = text[r.upperBound...]
        if suffix.hasPrefix("true") { return true }
        if suffix.hasPrefix("false") { return false }
        return nil
    }

    private static func cleanInfoText(_ raw: String) -> String {
        var t = raw
        let noisePrefixes = ["SETTLING STATE CHANGE, ", "Guiding parameter change, "]
        for p in noisePrefixes where t.hasPrefix(p) {
            t = String(t.dropFirst(p.count))
        }
        if t.hasPrefix("DITHER"), let r = t.range(of: ", new lock pos") {
            t = String(t[..<r.lowerBound])
        }
        return t
    }
}

// MARK: - CSV tokenizer

enum CSVTokenizer {
    static func split(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false
        for c in line {
            if c == "\"" { inQuotes.toggle(); continue }
            if c == "," && !inQuotes {
                out.append(cur); cur = ""
            } else {
                cur.append(c)
            }
        }
        out.append(cur)
        return out
    }
}

// MARK: - ISO date parsing (YYYY-MM-DD HH:MM:SS)

enum ISODateParser {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone.current
        return f
    }()
    static func parse(_ s: String) -> Date? {
        formatter.date(from: s.trimmingCharacters(in: .whitespaces))
    }
}
