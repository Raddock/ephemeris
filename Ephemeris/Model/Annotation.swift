import Foundation

/// User-recorded event tied to a night. Captures what the engine cannot observe directly.
///
/// Per design doc §9 and throughline #3 ("Know what the user did"). Annotations are the
/// load-bearing mechanism for events like the OAG-damage → repair → sky-model sequence
/// from §13.2 — the engine sees consequences in the logs but can't attribute them
/// without the user's testimony.
struct Annotation: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var rigProfileId: UUID
    var nightRecordId: UUID?
    var eventDate: Date
    var categories: Set<AnnotationCategory>
    /// Short, displayed on charts and in row badges. e.g. "OAG damaged".
    var label: String
    /// Longer free-text detail. Markdown-light.
    var detail: String
    /// When true, the recommender treats post-event sessions as a new regime per §6.5.
    /// Also surfaces a follow-up prompt to update the `RigProfile` (focal length, camera, etc.).
    var isRigMutating: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        rigProfileId: UUID,
        nightRecordId: UUID? = nil,
        eventDate: Date,
        categories: Set<AnnotationCategory> = [],
        label: String,
        detail: String = "",
        isRigMutating: Bool = false,
        createdAt: Date = .now,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.rigProfileId = rigProfileId
        self.nightRecordId = nightRecordId
        self.eventDate = eventDate
        self.categories = categories
        self.label = label
        self.detail = detail
        self.isRigMutating = isRigMutating
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

extension Annotation {
    /// Build a value-type Annotation from a SwiftData AnnotationEntity. Phase 7 wiring
    /// uses this in `LibraryDetailView` to feed the cross-night engine which only knows
    /// the pure-Swift type.
    @MainActor
    init?(entity: AnnotationEntity) {
        let rawCategories = (try? JSONDecoder().decode([String].self, from: entity.categoriesData)) ?? []
        let categories = Set(rawCategories.compactMap { AnnotationCategory(rawValue: $0) })
        self.init(
            id: entity.id,
            rigProfileId: entity.rigProfileId,
            nightRecordId: entity.nightRecord?.id,
            eventDate: entity.eventDate,
            categories: categories,
            label: entity.label,
            detail: entity.detail,
            isRigMutating: entity.isRigMutating,
            createdAt: entity.createdAt,
            modifiedAt: entity.modifiedAt
        )
    }
}

extension AnnotationCategory {
    /// Display label shown on the multi-select chip strip.
    var displayName: String {
        switch self {
        case .equipment:   return "Equipment"
        case .calibration: return "Calibration"
        case .environment: return "Environment"
        case .software:    return "Software"
        case .freeText:    return "Free text"
        }
    }

    /// SF Symbol used by the chip strip and the annotation row badges.
    var symbolName: String {
        switch self {
        case .equipment:   return "wrench.and.screwdriver"
        case .calibration: return "scope"
        case .environment: return "cloud.sun"
        case .software:    return "gear"
        case .freeText:    return "text.bubble"
        }
    }
}
