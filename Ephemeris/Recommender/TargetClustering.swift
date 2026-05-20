import Foundation

/// Phase 9 — pointing/target awareness. Clusters NightRecords by RA/Dec proximity
/// so the recommender (and MCP clients) can answer "how do my Andromeda nights
/// compare to my Orion nights?" without the user having to label each session.
///
/// **Algorithm**: greedy, incremental. For each night with a valid pointing, we
/// either:
///   1. Merge into the closest existing cluster whose center is within `radiusDeg`
///      (using haversine angular separation, declination-aware), OR
///   2. Create a new cluster centered on that night.
/// After assignment we recompute each cluster's center as the frame-count-weighted
/// median pointing of its members, refresh its catalog match against the Messier
/// catalog (within 0.5°), and roll up session count / integration / median RMS.
///
/// `defaultClusterRadiusDeg = 0.5` matches the Messier-match tolerance —
/// distinct catalog objects at that radius are a deliberate split, not a clustering
/// failure.
nonisolated enum TargetClustering {
    static let defaultClusterRadiusDeg: Double = 0.5

    /// Pure-value summary of a member night used by the algorithm.
    struct NightPoint: Sendable {
        let id: UUID
        let raHours: Double
        let decDegrees: Double
        let totalIntegrationMinutes: Double
        let medianRMSArcsec: Double
    }

    /// Pure-value cluster description that the SwiftData layer materializes into
    /// `TargetClusterEntity` rows.
    struct Cluster: Sendable {
        let id: UUID
        var centerRA: Double         // hours
        var centerDec: Double        // degrees
        var radiusDeg: Double
        var catalogMatch: String?
        var nightIDs: [UUID]
        var sessionCount: Int        // sum of member night sessions
        var totalIntegrationMinutes: Double
        var medianRMSArcsec: Double
    }

    /// Group nights into clusters from scratch. Stateless — the caller is
    /// responsible for diffing the result against existing `TargetClusterEntity`
    /// rows. Nights without a pointing are skipped.
    static func cluster(nights: [NightPoint],
                        rigSessionsByNight: [UUID: Int],
                        radiusDeg: Double = defaultClusterRadiusDeg) -> [Cluster] {
        // Sort by integration time descending — nights with more imaging time
        // anchor clusters first so a short scouting frame doesn't seed a cluster
        // that a real imaging run would have joined.
        let ordered = nights.sorted { $0.totalIntegrationMinutes > $1.totalIntegrationMinutes }
        var clusters: [Cluster] = []

        for night in ordered {
            // Find the nearest existing cluster within radius.
            var bestIndex: Int?
            var bestSep = Double.greatestFiniteMagnitude
            for (index, cluster) in clusters.enumerated() {
                let sep = angularSeparationDeg(
                    ra1Hours: night.raHours, dec1Degrees: night.decDegrees,
                    ra2Hours: cluster.centerRA, dec2Degrees: cluster.centerDec
                )
                if sep <= radiusDeg && sep < bestSep {
                    bestSep = sep
                    bestIndex = index
                }
            }
            if let idx = bestIndex {
                clusters[idx].nightIDs.append(night.id)
            } else {
                clusters.append(Cluster(
                    id: UUID(),
                    centerRA: night.raHours,
                    centerDec: night.decDegrees,
                    radiusDeg: radiusDeg,
                    catalogMatch: MessierCatalog.match(
                        raHours: night.raHours, decDegrees: night.decDegrees
                    )?.identifier,
                    nightIDs: [night.id],
                    sessionCount: 0,
                    totalIntegrationMinutes: 0,
                    medianRMSArcsec: 0
                ))
            }
        }

        // Refine each cluster's center / catalog / rollups now that all members
        // are assigned. Center is the integration-weighted mean pointing.
        for index in clusters.indices {
            let members = clusters[index].nightIDs.compactMap { id in
                nights.first(where: { $0.id == id })
            }
            guard !members.isEmpty else { continue }
            let totalWeight = members.reduce(0.0) { $0 + max(1.0, $1.totalIntegrationMinutes) }
            let weightedRA = members.reduce(0.0) {
                $0 + $1.raHours * max(1.0, $1.totalIntegrationMinutes)
            } / totalWeight
            let weightedDec = members.reduce(0.0) {
                $0 + $1.decDegrees * max(1.0, $1.totalIntegrationMinutes)
            } / totalWeight
            clusters[index].centerRA = weightedRA
            clusters[index].centerDec = weightedDec
            clusters[index].catalogMatch = MessierCatalog.match(
                raHours: weightedRA, decDegrees: weightedDec
            )?.identifier
            clusters[index].sessionCount = members.reduce(0) { $0 + (rigSessionsByNight[$1.id] ?? 0) }
            clusters[index].totalIntegrationMinutes = members.reduce(0.0) {
                $0 + $1.totalIntegrationMinutes
            }
            // Frame-count-weighted RMS would be more accurate, but at the night-
            // rollup layer we only have per-night medians; a plain median across
            // member nights is the right granularity here.
            let rmsValues = members.map { $0.medianRMSArcsec }.filter { $0 > 0 }.sorted()
            clusters[index].medianRMSArcsec = rmsValues.isEmpty ? 0 : rmsValues[rmsValues.count / 2]
        }

        return clusters
    }

    /// Spherical haversine, in degrees. Same math as `Astronomy.angularSeparationDeg`
    /// but inlined here so the clustering algorithm stays a closed unit.
    private static func angularSeparationDeg(ra1Hours: Double, dec1Degrees: Double,
                                             ra2Hours: Double, dec2Degrees: Double) -> Double {
        let a1 = ra1Hours * 15.0 * .pi / 180.0
        let d1 = dec1Degrees * .pi / 180.0
        let a2 = ra2Hours * 15.0 * .pi / 180.0
        let d2 = dec2Degrees * .pi / 180.0
        let dA = a2 - a1
        let dD = d2 - d1
        let h = sin(dD / 2) * sin(dD / 2) +
                cos(d1) * cos(d2) * sin(dA / 2) * sin(dA / 2)
        return 2 * asin(min(1, sqrt(h))) * 180.0 / .pi
    }
}
