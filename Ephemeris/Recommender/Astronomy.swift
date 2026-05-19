import Foundation

/// Per design doc §6.2 throughline #8 (pointing context normalizes confounds).
/// Coordinate transforms + a small catalog lookup so target-aware observations
/// can normalize star-count expectations by galactic latitude.
enum Astronomy {

    /// Convert equatorial coordinates (J2000) to galactic latitude in degrees.
    /// Used by the recommender to bin nights by galactic environment.
    ///
    /// Constants per IAU 1958 / J2000 NGP definitions.
    static func galacticLatitude(raHours: Double, decDegrees: Double) -> Double {
        let alpha = raHours * 15.0 * .pi / 180.0   // hours → radians
        let delta = decDegrees * .pi / 180.0

        // Galactic North Pole (J2000)
        let alphaNGP = 192.85948 * .pi / 180.0
        let deltaNGP = 27.12825 * .pi / 180.0

        let sinB = sin(deltaNGP) * sin(delta) +
                   cos(deltaNGP) * cos(delta) * cos(alpha - alphaNGP)
        return asin(sinB) * 180.0 / .pi
    }

    /// Approximate angular distance (degrees) between two equatorial coordinates.
    /// Uses the spherical haversine.
    static func angularSeparationDeg(
        ra1Hours: Double, dec1Degrees: Double,
        ra2Hours: Double, dec2Degrees: Double
    ) -> Double {
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

/// Compact catalog of popular Messier objects for target identification.
/// A full NGC catalog (~7800 entries) is deferred to v2.1. Messier covers the
/// targets that account for the majority of amateur imaging sessions.
struct CatalogObject: Sendable {
    let identifier: String   // e.g. "M31"
    let commonName: String   // e.g. "Andromeda Galaxy"
    let raHours: Double      // J2000 right ascension
    let decDegrees: Double   // J2000 declination
}

enum MessierCatalog {
    /// Try to resolve a pointing to a Messier object. Returns the nearest catalog entry
    /// within `toleranceDeg` (default 0.5°), or nil if nothing's close enough.
    static func match(raHours: Double, decDegrees: Double, toleranceDeg: Double = 0.5) -> CatalogObject? {
        var bestMatch: (CatalogObject, Double)?
        for entry in all {
            let sep = Astronomy.angularSeparationDeg(
                ra1Hours: raHours, dec1Degrees: decDegrees,
                ra2Hours: entry.raHours, dec2Degrees: entry.decDegrees
            )
            if sep <= toleranceDeg, sep < (bestMatch?.1 ?? .greatestFiniteMagnitude) {
                bestMatch = (entry, sep)
            }
        }
        return bestMatch?.0
    }

    /// 50 most-imaged Messier objects with J2000 RA/Dec. Covers the typical northern
    /// astrophotography target set. Sourced from standard Messier catalog references.
    static let all: [CatalogObject] = [
        CatalogObject(identifier: "M1",   commonName: "Crab Nebula",          raHours: 5.5755,  decDegrees:  22.0145),
        CatalogObject(identifier: "M8",   commonName: "Lagoon Nebula",        raHours: 18.0633, decDegrees: -24.3833),
        CatalogObject(identifier: "M13",  commonName: "Hercules Cluster",     raHours: 16.6949, decDegrees:  36.4613),
        CatalogObject(identifier: "M16",  commonName: "Eagle Nebula",         raHours: 18.3133, decDegrees: -13.7833),
        CatalogObject(identifier: "M17",  commonName: "Omega Nebula",         raHours: 18.3467, decDegrees: -16.1833),
        CatalogObject(identifier: "M20",  commonName: "Trifid Nebula",        raHours: 18.0367, decDegrees: -23.0333),
        CatalogObject(identifier: "M22",  commonName: "Sagittarius Cluster",  raHours: 18.6067, decDegrees: -23.9000),
        CatalogObject(identifier: "M27",  commonName: "Dumbbell Nebula",      raHours: 19.9933, decDegrees:  22.7211),
        CatalogObject(identifier: "M31",  commonName: "Andromeda Galaxy",     raHours: 0.7122,  decDegrees:  41.2692),
        CatalogObject(identifier: "M33",  commonName: "Triangulum Galaxy",    raHours: 1.5642,  decDegrees:  30.6602),
        CatalogObject(identifier: "M35",  commonName: "Gemini Cluster",       raHours: 6.1483,  decDegrees:  24.3333),
        CatalogObject(identifier: "M37",  commonName: "Auriga Cluster",       raHours: 5.8717,  decDegrees:  32.5500),
        CatalogObject(identifier: "M42",  commonName: "Orion Nebula",         raHours: 5.5883,  decDegrees:  -5.3911),
        CatalogObject(identifier: "M44",  commonName: "Beehive Cluster",      raHours: 8.6700,  decDegrees:  19.9833),
        CatalogObject(identifier: "M45",  commonName: "Pleiades",             raHours: 3.7900,  decDegrees:  24.1167),
        CatalogObject(identifier: "M46",  commonName: "Puppis Cluster",       raHours: 7.6967,  decDegrees: -14.8167),
        CatalogObject(identifier: "M51",  commonName: "Whirlpool Galaxy",     raHours: 13.4983, decDegrees:  47.1953),
        CatalogObject(identifier: "M57",  commonName: "Ring Nebula",          raHours: 18.8917, decDegrees:  33.0297),
        CatalogObject(identifier: "M63",  commonName: "Sunflower Galaxy",     raHours: 13.2633, decDegrees:  42.0297),
        CatalogObject(identifier: "M64",  commonName: "Black Eye Galaxy",     raHours: 12.9450, decDegrees:  21.6825),
        CatalogObject(identifier: "M65",  commonName: "Leo Triplet (M65)",    raHours: 11.3158, decDegrees:  13.0922),
        CatalogObject(identifier: "M66",  commonName: "Leo Triplet (M66)",    raHours: 11.3375, decDegrees:  12.9914),
        CatalogObject(identifier: "M74",  commonName: "Phantom Galaxy",       raHours: 1.6117,  decDegrees:  15.7836),
        CatalogObject(identifier: "M76",  commonName: "Little Dumbbell",      raHours: 1.7050,  decDegrees:  51.5750),
        CatalogObject(identifier: "M77",  commonName: "Cetus A",              raHours: 2.7117,  decDegrees:  -0.0133),
        CatalogObject(identifier: "M78",  commonName: "M78",                  raHours: 5.7783,  decDegrees:   0.0789),
        CatalogObject(identifier: "M81",  commonName: "Bode's Galaxy",        raHours: 9.9258,  decDegrees:  69.0653),
        CatalogObject(identifier: "M82",  commonName: "Cigar Galaxy",         raHours: 9.9317,  decDegrees:  69.6797),
        CatalogObject(identifier: "M84",  commonName: "Markarian's Chain",    raHours: 12.4183, decDegrees:  12.8867),
        CatalogObject(identifier: "M87",  commonName: "Virgo A",              raHours: 12.5133, decDegrees:  12.3911),
        CatalogObject(identifier: "M92",  commonName: "M92 cluster",          raHours: 17.2867, decDegrees:  43.1361),
        CatalogObject(identifier: "M95",  commonName: "M95",                  raHours: 10.7333, decDegrees:  11.7036),
        CatalogObject(identifier: "M96",  commonName: "M96",                  raHours: 10.7783, decDegrees:  11.8200),
        CatalogObject(identifier: "M97",  commonName: "Owl Nebula",           raHours: 11.2467, decDegrees:  55.0192),
        CatalogObject(identifier: "M100", commonName: "M100",                 raHours: 12.3817, decDegrees:  15.8225),
        CatalogObject(identifier: "M101", commonName: "Pinwheel Galaxy",      raHours: 14.0533, decDegrees:  54.3489),
        CatalogObject(identifier: "M103", commonName: "M103",                 raHours: 1.5550,  decDegrees:  60.6583),
        CatalogObject(identifier: "M104", commonName: "Sombrero Galaxy",      raHours: 12.6667, decDegrees: -11.6233),
        CatalogObject(identifier: "M106", commonName: "M106",                 raHours: 12.3167, decDegrees:  47.3033),
        CatalogObject(identifier: "M108", commonName: "Surfboard Galaxy",     raHours: 11.1933, decDegrees:  55.6739),
        CatalogObject(identifier: "M109", commonName: "M109",                 raHours: 11.9617, decDegrees:  53.3742),
    ]
}
