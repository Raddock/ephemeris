import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Phase 3 deliverable per design §10: donate `NightRecord` and `Annotation` rows
/// to CoreSpotlight so the user can find a night ("May 17 0.38″") or a noted
/// equipment event ("OAG fix") via macOS Spotlight without opening Ephemeris.
///
/// Donations are best-effort: indexing failures are logged and otherwise ignored.
/// CoreSpotlight de-duplicates by `uniqueIdentifier`, so calling `donate` repeatedly
/// for the same UUID just refreshes the index entry — that's the behavior we want
/// after each `LibraryIngestor.ingest()` recomputes the night's aggregates.
///
/// We use a single shared `domainIdentifier` so a "Reset library data" action can
/// remove every Ephemeris donation in one call to
/// `deleteSearchableItems(withDomainIdentifiers:)`.
nonisolated enum CoreSpotlightIndexer {
    static let domainIdentifier = "com.macobservatory.Ephemeris.library"

    nonisolated static func donate(night: NightRecordEntityDigest) {
        let attr = CSSearchableItemAttributeSet(contentType: .data)
        attr.title = night.title
        attr.contentDescription = night.subtitle
        attr.keywords = night.keywords
        attr.contentCreationDate = night.nightDate
        attr.contentModificationDate = night.lastAnalyzedAt
        let item = CSSearchableItem(
            uniqueIdentifier: "ephemeris://night/\(night.id.uuidString)",
            domainIdentifier: domainIdentifier,
            attributeSet: attr
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                NSLog("[CoreSpotlight] Night index failed for %@ — %@",
                      night.id.uuidString, error.localizedDescription)
            }
        }
    }

    nonisolated static func donate(annotation: AnnotationEntityDigest) {
        let attr = CSSearchableItemAttributeSet(contentType: .data)
        attr.title = annotation.title
        attr.contentDescription = annotation.subtitle
        attr.keywords = annotation.keywords
        attr.contentCreationDate = annotation.eventDate
        attr.contentModificationDate = annotation.modifiedAt
        let item = CSSearchableItem(
            uniqueIdentifier: "ephemeris://annotation/\(annotation.id.uuidString)",
            domainIdentifier: domainIdentifier,
            attributeSet: attr
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                NSLog("[CoreSpotlight] Annotation index failed for %@ — %@",
                      annotation.id.uuidString, error.localizedDescription)
            }
        }
    }

    /// Remove every Ephemeris donation. Called by the Settings → Reset library data
    /// flow so Spotlight stops surfacing nights/annotations that no longer exist.
    nonisolated static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
            if let error {
                NSLog("[CoreSpotlight] Remove-all failed: %@", error.localizedDescription)
            }
        }
    }
}

/// Value-type snapshot of a NightRecord that's safe to ship across actor boundaries.
/// The `@ModelActor` ingest can build one of these and hand it to `CoreSpotlightIndexer`
/// without re-entering the main actor.
struct NightRecordEntityDigest: Sendable {
    let id: UUID
    let title: String        // e.g. "May 17, 2026 · Edge-10m · 0.38″"
    let subtitle: String     // e.g. "3 sessions · 36 min · M31 · galactic +20°"
    let keywords: [String]   // rig name, catalog match, severity, etc.
    let nightDate: Date
    let lastAnalyzedAt: Date
}

struct AnnotationEntityDigest: Sendable {
    let id: UUID
    let title: String        // e.g. "Equipment · Replaced OAG prism"
    let subtitle: String     // detail truncated
    let keywords: [String]
    let eventDate: Date
    let modifiedAt: Date
}
