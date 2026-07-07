//
//  GuideChartData.swift
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

/// Downsampled, precomputed model for the guide charts.
///
/// A full night of guiding is 50k–200k frames while the plot area is one to two
/// thousand points wide. Swift Charts degrades badly past a few thousand marks,
/// so the views never plot raw entries: they plot this model, rebuilt only when
/// the session, axis mode, or zoom domain changes — never per hover tick.
///
/// Decimation is per-bucket first/min/max/last (the standard line-chart
/// reduction): extremes always survive, so spikes a user must see are never
/// smoothed away, and the cached magnitudes make the y-domain O(1). Unit
/// conversion (px → arcsec) is a positive linear scale, so it happens at mark
/// time without affecting which points are extremes.
nonisolated struct GuideChartData {

    /// Identity of a computed model. Views cache one model and rebuild when
    /// this key changes; hover state is deliberately not part of the key.
    struct Key: Equatable, Sendable {
        let sessionID: UUID
        let axisMode: ChartViewState.AxisMode
        let domainLo: Double?
        let domainHi: Double?
    }

    struct SeriesPoint: Identifiable, Sendable {
        let id: Int
        let time: Double
        /// Value in pixels. NaN marks a gap sentinel: Swift Charts breaks the
        /// line there, exactly as it did when plotting raw entries.
        let valuePx: Double
    }

    struct EventMarkerData: Identifiable, Sendable {
        let id: Int
        let time: Double
        let kind: InfoKind
    }

    struct SettlingBandData: Identifiable, Sendable {
        let id: Int
        let startTime: Double
        let endTime: Double
        let succeeded: Bool
    }

    /// Target bucket count. Up to 4 emitted points per bucket keeps each series
    /// under ~3k marks, comfortably inside Swift Charts' budget.
    static let defaultBucketCount = 700

    let key: Key
    let raPoints: [SeriesPoint]
    let decPoints: [SeriesPoint]
    let raCorrections: [SeriesPoint]
    let decCorrections: [SeriesPoint]
    /// Largest |value| in px among included entries inside the domain.
    let maxSeriesMagnitudePx: Double
    let maxCorrectionMagnitudePx: Double
    let eventMarkers: [EventMarkerData]
    let settlingBands: [SettlingBandData]

    private let entries: [GuideEntry]
    /// Times of real (non-sentinel) entries, ascending, for O(log n) hover lookup.
    private let realTimes: [Double]
    private let realIndices: [Int]

    init(session: GuideSession, key: Key, bucketCount: Int = GuideChartData.defaultBucketCount) {
        self.key = key
        self.entries = session.entries

        let domain: ClosedRange<Double>?
        if let lo = key.domainLo, let hi = key.domainHi, lo < hi {
            domain = lo...hi
        } else {
            domain = nil
        }

        // One pass: hover index, y-domain magnitudes, and the candidate ranges.
        var realTimes: [Double] = []
        var realIndices: [Int] = []
        realTimes.reserveCapacity(session.entries.count)
        realIndices.reserveCapacity(session.entries.count)
        var maxSeries = 0.0
        var maxCorrection = 0.0

        let raDec = (key.axisMode == .raDec)
        func rawX(_ e: GuideEntry) -> Double { raDec ? e.raRawDistance : e.dx }
        func rawY(_ e: GuideEntry) -> Double { raDec ? e.decRawDistance : e.dy }
        func device(_ e: GuideEntry) -> GuideDevice {
            e.deviceKind == .ao ? (session.ao ?? session.mount) : session.mount
        }
        func corrRA(_ e: GuideEntry) -> Double { Double(e.raDuration) / 1000.0 * device(e).xRate }
        func corrDec(_ e: GuideEntry) -> Double { Double(e.decDuration) / 1000.0 * device(e).yRate }

        for (i, e) in session.entries.enumerated() {
            if !e.raRawDistance.isNaN {
                realTimes.append(e.time)
                realIndices.append(i)
            }
            guard e.included else { continue }
            if let domain, !domain.contains(e.time) { continue }
            maxSeries = max(maxSeries, abs(rawX(e)), abs(rawY(e)))
            if e.raDuration != 0 { maxCorrection = max(maxCorrection, abs(corrRA(e))) }
            if e.decDuration != 0 { maxCorrection = max(maxCorrection, abs(corrDec(e))) }
        }
        self.realTimes = realTimes
        self.realIndices = realIndices
        self.maxSeriesMagnitudePx = maxSeries
        self.maxCorrectionMagnitudePx = maxCorrection

        self.raPoints = Self.decimate(session.entries, domain: domain,
                                      bucketCount: bucketCount, value: rawX)
        self.decPoints = Self.decimate(session.entries, domain: domain,
                                       bucketCount: bucketCount, value: rawY)
        self.raCorrections = Self.decimateCorrections(session.entries, domain: domain,
                                                      bucketCount: bucketCount, value: corrRA,
                                                      hasValue: { $0.raDuration != 0 })
        self.decCorrections = Self.decimateCorrections(session.entries, domain: domain,
                                                       bucketCount: bucketCount, value: corrDec,
                                                       hasValue: { $0.decDuration != 0 })

        // Events and settling bands: small, but the frame→time lookup used to
        // re-filter the whole entry array per info line. Filter once here.
        var realFrames: [(frame: Int, time: Double)] = []
        realFrames.reserveCapacity(realIndices.count)
        for i in realIndices {
            realFrames.append((session.entries[i].frame, session.entries[i].time))
        }
        func entryTime(forFrame frame: Int) -> Double? {
            guard !realFrames.isEmpty else { return nil }
            if frame <= 0 { return realFrames.first?.time }
            if let hit = realFrames.first(where: { $0.frame >= frame }) { return hit.time }
            return realFrames.last?.time
        }

        var markers: [EventMarkerData] = []
        var seenFrames = Set<Int>()
        var bands: [SettlingBandData] = []
        var pendingStartFrame: Int?
        var bandID = 0
        for info in session.infos {
            let kind = info.kind
            switch kind {
            case .settlingStarted:
                pendingStartFrame = info.frame
                continue
            case .settlingComplete, .settlingFailed:
                if let startFrame = pendingStartFrame,
                   let start = entryTime(forFrame: startFrame),
                   let end = entryTime(forFrame: info.frame) {
                    bands.append(SettlingBandData(
                        id: bandID,
                        startTime: start,
                        endTime: max(end, start + 0.001),
                        succeeded: kind == .settlingComplete
                    ))
                    bandID += 1
                    pendingStartFrame = nil
                }
                continue
            default:
                break
            }
            guard !seenFrames.contains(info.frame) else { continue }
            seenFrames.insert(info.frame)
            guard let t = entryTime(forFrame: info.frame) else { continue }
            markers.append(EventMarkerData(id: info.frame, time: t, kind: kind))
        }
        self.eventMarkers = markers
        self.settlingBands = bands
    }

    /// Nearest real (non-sentinel) entry to a hover time. Binary search; the old
    /// per-hover full scan re-ran on every mouse-move event.
    func nearestRealEntry(to t: Double) -> GuideEntry? {
        guard !realTimes.isEmpty else { return nil }
        var lo = 0
        var hi = realTimes.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if realTimes[mid] < t { lo = mid + 1 } else { hi = mid }
        }
        var best = lo
        if lo > 0, abs(realTimes[lo - 1] - t) <= abs(realTimes[lo] - t) {
            best = lo - 1
        }
        return entries[realIndices[best]]
    }

    // MARK: - Decimation

    /// First/min/max/last per time bucket. Gap sentinels (NaN values) are
    /// emitted verbatim so line breaks survive. Series already inside the
    /// budget are passed through unchanged.
    static func decimate(_ entries: [GuideEntry],
                         domain: ClosedRange<Double>?,
                         bucketCount: Int,
                         value: (GuideEntry) -> Double) -> [SeriesPoint] {
        let candidates = candidateIndices(entries, domain: domain)
        guard candidates.count > bucketCount * 4 else {
            return candidates.map { i in
                SeriesPoint(id: i, time: entries[i].time, valuePx: value(entries[i]))
            }
        }

        let lo = entries[candidates.first!].time
        let hi = entries[candidates.last!].time
        let width = (hi - lo) / Double(bucketCount)
        guard width > 0 else {
            return candidates.map { i in
                SeriesPoint(id: i, time: entries[i].time, valuePx: value(entries[i]))
            }
        }

        var out: [SeriesPoint] = []
        out.reserveCapacity(bucketCount * 4 + 8)
        var currentBucket = -1
        var first = -1, last = -1, minIdx = -1, maxIdx = -1
        var minV = Double.infinity, maxV = -Double.infinity

        func flush() {
            guard first >= 0 else { return }
            var picks = [first, minIdx, maxIdx, last].filter { $0 >= 0 }
            picks = Array(Set(picks)).sorted()
            for i in picks {
                out.append(SeriesPoint(id: i, time: entries[i].time, valuePx: value(entries[i])))
            }
            first = -1; last = -1; minIdx = -1; maxIdx = -1
            minV = .infinity; maxV = -.infinity
        }

        for i in candidates {
            let v = value(entries[i])
            if v.isNaN {
                // Gap sentinel: close the current bucket and emit the break.
                flush()
                out.append(SeriesPoint(id: i, time: entries[i].time, valuePx: .nan))
                currentBucket = -1
                continue
            }
            let bucket = min(bucketCount - 1, max(0, Int((entries[i].time - lo) / width)))
            if bucket != currentBucket {
                flush()
                currentBucket = bucket
            }
            if first < 0 { first = i }
            last = i
            if v < minV { minV = v; minIdx = i }
            if v > maxV { maxV = v; maxIdx = i }
        }
        flush()
        return out
    }

    /// Correction bars: keep the worst (largest-magnitude) correction per bucket
    /// and direction. At zoomed-out scale individual 20 ms pulses are invisible;
    /// what must survive is the biggest correction the mount made.
    static func decimateCorrections(_ entries: [GuideEntry],
                                    domain: ClosedRange<Double>?,
                                    bucketCount: Int,
                                    value: (GuideEntry) -> Double,
                                    hasValue: (GuideEntry) -> Bool) -> [SeriesPoint] {
        let candidates = candidateIndices(entries, domain: domain).filter {
            entries[$0].included && hasValue(entries[$0])
        }
        guard candidates.count > bucketCount * 2 else {
            return candidates.map { i in
                SeriesPoint(id: i, time: entries[i].time, valuePx: value(entries[i]))
            }
        }

        let lo = entries[candidates.first!].time
        let hi = entries[candidates.last!].time
        let width = (hi - lo) / Double(bucketCount)
        guard width > 0 else {
            return candidates.map { i in
                SeriesPoint(id: i, time: entries[i].time, valuePx: value(entries[i]))
            }
        }

        var out: [SeriesPoint] = []
        out.reserveCapacity(bucketCount + 4)
        var currentBucket = -1
        var bestIdx = -1
        var bestMag = -Double.infinity

        func flush() {
            guard bestIdx >= 0 else { return }
            out.append(SeriesPoint(id: bestIdx, time: entries[bestIdx].time,
                                   valuePx: value(entries[bestIdx])))
            bestIdx = -1
            bestMag = -.infinity
        }

        for i in candidates {
            let v = value(entries[i])
            guard !v.isNaN else { continue }
            let bucket = min(bucketCount - 1, max(0, Int((entries[i].time - lo) / width)))
            if bucket != currentBucket {
                flush()
                currentBucket = bucket
            }
            if abs(v) > bestMag {
                bestMag = abs(v)
                bestIdx = i
            }
        }
        flush()
        return out
    }

    /// Indices inside the domain, plus one neighbor on each side so a zoomed
    /// line enters and exits the plot instead of stopping at the first inside
    /// point. Nil domain means everything.
    private static func candidateIndices(_ entries: [GuideEntry],
                                         domain: ClosedRange<Double>?) -> [Int] {
        guard let domain else { return Array(entries.indices) }
        var out: [Int] = []
        var lastBefore: Int?
        var firstAfterTaken = false
        for i in entries.indices {
            let t = entries[i].time
            if t < domain.lowerBound {
                lastBefore = i
            } else if t > domain.upperBound {
                if !firstAfterTaken {
                    out.append(i)
                    firstAfterTaken = true
                }
            } else {
                if let b = lastBefore {
                    out.append(b)
                    lastBefore = nil
                }
                out.append(i)
            }
        }
        return out
    }
}

/// Decimated single-value series for the diagnostic strips (star mass / SNR).
/// Same caching contract as `GuideChartData`, without the correction/event extras.
nonisolated struct DiagnosticChartData {
    struct Key: Equatable, Sendable {
        let sessionID: UUID
        let kind: String
        let domainLo: Double
        let domainHi: Double
    }

    let key: Key
    let points: [GuideChartData.SeriesPoint]
    private let realTimes: [Double]
    private let realValues: [Double]
    private let realFrames: [Int]

    init(session: GuideSession, key: Key, value: (GuideEntry) -> Double,
         bucketCount: Int = GuideChartData.defaultBucketCount) {
        self.key = key
        // Sentinels carry zero star mass / SNR (not NaN) and would draw V-dips,
        // so they are dropped entirely rather than kept as breaks.
        let real = session.entries.filter { !$0.raRawDistance.isNaN }
        self.realTimes = real.map(\.time)
        self.realValues = real.map(value)
        self.realFrames = real.map(\.frame)
        self.points = GuideChartData.decimate(real, domain: key.domainLo < key.domainHi ? key.domainLo...key.domainHi : nil,
                                              bucketCount: bucketCount, value: value)
    }

    /// Nearest (time, value, frame) to a hover time, by binary search.
    func nearestValue(to t: Double) -> (time: Double, value: Double, frame: Int)? {
        guard !realTimes.isEmpty else { return nil }
        var lo = 0
        var hi = realTimes.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if realTimes[mid] < t { lo = mid + 1 } else { hi = mid }
        }
        var best = lo
        if lo > 0, abs(realTimes[lo - 1] - t) <= abs(realTimes[lo] - t) {
            best = lo - 1
        }
        return (realTimes[best], realValues[best], realFrames[best])
    }
}
