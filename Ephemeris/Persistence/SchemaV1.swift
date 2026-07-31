import Foundation
import SwiftData

/// v2.0 Phase 3 — SwiftData schema v1. Persistent library store backing the multi-night
/// library (Phase 6+) and the cross-night recommender (Phase 7).
///
/// **CloudKit-clean rules applied uniformly (design doc §4):**
/// 1. No `@Attribute(.unique)` constraints — uniqueness enforced by ingest `ModelActor`.
/// 2. Every `@Relationship` declared optional.
/// 3. Every attribute has a default value.
/// 4. Ordered `[String]` arrays stored via Codable-encoded `Data` when order matters.
///
/// Phase 1's `RigProfile` struct continues to back the rig-profile editor; Phase 3 will
/// migrate JSON-sidecar profiles into `RigProfileEntity` on first launch.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            RigProfileEntity.self,
            NightRecordEntity.self,
            SessionRecordEntity.self,
            ObservationEntity.self,
            AnnotationEntity.self,
            TargetClusterEntity.self,
            GAResultEntity.self,
        ]
    }
}

/// Persistent rig profile. Mirrors the v1 value type's shape.
@Model
final class RigProfileEntity {
    @Attribute(.allowsCloudEncryption) var id: UUID = UUID()
    var currentName: String = ""
    /// User-facing label; falls back to `currentName` when nil. Mirrors `RigProfile`.
    var displayName: String? = nil
    /// Codable-encoded array of historical names (SwiftData doesn't preserve array order).
    var nameHistoryData: Data = Data()

    var imagingFocalLengthMm: Double = 0
    var imagingPixelSizeMicrons: Double = 0
    var imagingBinning: Int = 1
    var reducerFactor: Double? = nil

    var guideConfigurationRaw: String = GuideConfiguration.oag.rawValue
    var guideCameraPixelSizeMicrons: Double = 0
    var guideFocalLengthMm: Double = 0
    var guideBinning: Int = 1

    var mountModel: String? = nil
    var mountClassRaw: String = MountClass.standardGearMount.rawValue
    var hasHighPrecisionEncoders: Bool = false

    var typicalSubExposure: Int? = nil
    var notes: String? = nil

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \NightRecordEntity.rigProfile)
    var nightRecords: [NightRecordEntity]? = nil

    @Relationship(deleteRule: .cascade, inverse: \TargetClusterEntity.rigProfile)
    var targetClusters: [TargetClusterEntity]? = nil

    init(from value: RigProfile) {
        self.id = value.id
        self.createdAt = value.createdAt
        update(from: value)
    }

    init() {}

    /// Refresh every mutable field from the value-type profile. Called by the
    /// rig-profile store on save and by ingest, both against this same entity —
    /// SwiftData is the single owner of rig-profile persistence.
    func update(from value: RigProfile) {
        currentName = value.currentName
        displayName = value.displayName
        nameHistoryData = (try? JSONEncoder().encode(value.nameHistory)) ?? Data()
        imagingFocalLengthMm = value.imagingFocalLength
        imagingPixelSizeMicrons = value.imagingPixelSize
        imagingBinning = value.imagingBinning
        reducerFactor = value.reducerFactor
        guideConfigurationRaw = value.guideConfiguration.rawValue
        guideCameraPixelSizeMicrons = value.guideCameraPixelSize
        guideFocalLengthMm = value.guideFocalLength
        guideBinning = value.guideBinning
        mountModel = value.mountModel
        mountClassRaw = value.mountClass.rawValue
        hasHighPrecisionEncoders = value.hasHighPrecisionEncoders
        typicalSubExposure = value.typicalSubExposure
        notes = value.notes
        modifiedAt = value.modifiedAt
    }

    var asValue: RigProfile {
        let history = (try? JSONDecoder().decode([String].self, from: nameHistoryData)) ?? []
        let cfg = GuideConfiguration(rawValue: guideConfigurationRaw) ?? .oag
        let mc = MountClass(rawValue: mountClassRaw) ?? .standardGearMount
        return RigProfile(
            id: id, currentName: currentName, nameHistory: history,
            displayName: displayName,
            imagingFocalLength: imagingFocalLengthMm,
            imagingPixelSize: imagingPixelSizeMicrons,
            imagingBinning: imagingBinning,
            reducerFactor: reducerFactor,
            guideConfiguration: cfg,
            guideCameraPixelSize: guideCameraPixelSizeMicrons,
            guideFocalLength: guideFocalLengthMm,
            guideBinning: guideBinning,
            mountModel: mountModel,
            mountClass: mc,
            hasHighPrecisionEncoders: hasHighPrecisionEncoders,
            typicalSubExposure: typicalSubExposure,
            notes: notes,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }
}

/// Per-night analytical artifact. One record per `.txt` log file ingested.
@Model
final class NightRecordEntity {
    var id: UUID = UUID()
    var rigProfile: RigProfileEntity? = nil

    /// File path the night was ingested from. Not authoritative — may be moved/deleted.
    var sourceFilePath: String = ""
    /// SHA-256 content hash. Uniqueness enforced in the ingest ModelActor.
    var sourceContentHash: String = ""

    var nightDate: Date = Date()
    var sessionsCount: Int = 0
    var totalIntegrationMinutes: Double = 0

    /// Frame-weighted quadrature-mean RMS for the night, NOT a median. The stored
    /// attribute keeps its original name because renaming it is a schema change
    /// (and the stdio helper reads the raw column); every in-memory type, UI label,
    /// and MCP field calls this "night RMS". Rename the attribute at SchemaV2.
    var medianRMSArcsec: Double = 0
    var bestSessionRMSArcsec: Double = 0
    var worstSessionRMSArcsec: Double = 0

    /// Median calibration orthogonality error (degrees, unsigned) for this night —
    /// from calibrations performed in the log, falling back to the session header's
    /// "ortho.err." figure. Feeds the cross-night CalibrationAngleShiftObserver.
    var calibrationOrthogonalityDeg: Double? = nil

    /// JSON-encoded `[PersistedSessionStats]`. Phase 3 will define the inner shape.
    var sessionStatsData: Data = Data()
    /// JSON-encoded `PersistedCalibration?`. Phase 3 will define the inner shape.
    var calibrationData: Data = Data()

    var ingestedAt: Date = Date()
    var lastAnalyzedAt: Date = Date()

    /// Phase 10: user-reported sub-quality verdict for this night's imaging frames.
    /// Stored as the raw value of `SubQualityVerdict`; nil = not yet rated.
    /// Per design §6.2 throughline #9: the imaging frame is ground truth, not the
    /// guide log — this is the user's testimony that the engine can't otherwise observe.
    var subQualityRaw: String? = nil

    // Phase 9: target / pointing context derived from session header at ingest time.
    /// Median RA (hours) across this night's sessions.
    var medianRAHours: Double? = nil
    /// Median Dec (degrees) across this night's sessions.
    var medianDecDegrees: Double? = nil
    /// Galactic latitude (degrees) of the median pointing — used to normalize star-count
    /// expectations. Below ±10° = in-plane, dense star fields; > 40° = high latitude, sparse.
    var galacticLatitudeDeg: Double? = nil
    /// Best Messier catalog match for the median pointing, if within ±0.5°. e.g. "M31".
    var catalogIdentifier: String? = nil
    /// Friendly catalog name, e.g. "Andromeda Galaxy".
    var catalogCommonName: String? = nil

    @Relationship(deleteRule: .cascade, inverse: \ObservationEntity.nightRecord)
    var observations: [ObservationEntity]? = nil

    @Relationship(deleteRule: .cascade, inverse: \AnnotationEntity.nightRecord)
    var annotations: [AnnotationEntity]? = nil

    @Relationship(deleteRule: .cascade, inverse: \GAResultEntity.nightRecord)
    var gaResults: [GAResultEntity]? = nil

    @Relationship(deleteRule: .cascade, inverse: \SessionRecordEntity.nightRecord)
    var sessionRecords: [SessionRecordEntity]? = nil

    init() {}
}

/// Per-session analytical artifact. One row per `GuideSession` inside the log.
/// Surfaces within-night detail (start time, altitude, RMS-per-session) so MCP
/// clients can test time-of-night / pointing-dependent hypotheses that night-level
/// rollups can't answer.
@Model
final class SessionRecordEntity {
    var id: UUID = UUID()
    var nightRecord: NightRecordEntity? = nil
    /// Denormalized rig id so MCP queries don't need a two-level join.
    var rigProfileId: UUID = UUID()
    /// 0-based order of this session within its night, by `startedAt`.
    var sessionIndex: Int = 0

    var startedAt: Date? = nil
    var durationSec: Double = 0

    // RMS (arcsec, after multiplying by pixel scale)
    var rmsTotalArcsec: Double = 0
    var rmsRAArcsec: Double = 0
    var rmsDecArcsec: Double = 0
    // Peak excursion (arcsec)
    var peakRAArcsec: Double = 0
    var peakDecArcsec: Double = 0
    // Drift (arcsec/min)
    var driftRAArcsecPerMin: Double = 0
    var driftDecArcsecPerMin: Double = 0
    var polarAlignErrorArcmin: Double = 0

    var includedFrames: Int = 0
    var excludedFrames: Int = 0
    /// Guide pixel scale (arcsec/px) at the time the session ran.
    var pixelScale: Double = 1.0

    // Pointing + geometry (parsed from session header)
    var raHours: Double? = nil
    var decDegrees: Double? = nil
    var hourAngleHours: Double? = nil
    var altitudeDegrees: Double? = nil
    var azimuthDegrees: Double? = nil
    var pierSide: String? = nil
    var hfdPixels: Double? = nil
    var exposureMs: Int? = nil
    var multiStarEnabled: Bool = false

    init() {}
}

/// Persistent observation. Mirrors the value-type `RecommenderObservation`.
@Model
final class ObservationEntity {
    var id: UUID = UUID()
    var nightRecord: NightRecordEntity? = nil
    var rigProfileId: UUID = UUID()

    var scopeRaw: String = "singleNight"
    var categoryRaw: Int = 0
    var severityRaw: Int = 0
    var sourceAuthorityRaw: String = "ephemerisHeuristic"
    var confidenceRaw: String = "medium"

    var title: String = ""
    var summary: String = ""
    var suggestedResponse: String = ""

    /// Start time of the source guide session for session-anchored findings;
    /// nil for night-level ones. Mirrors `RecommenderObservation.sessionStartedAt`.
    var sessionStartedAt: Date? = nil

    /// JSON-encoded `[EvidenceItem]`.
    var evidenceData: Data = Data()
    /// JSON-encoded `[String]`.
    var candidateContributorsData: Data = Data()
    /// JSON-encoded `[String]` of help topic IDs.
    var relatedHelpTopicIdsData: Data = Data()
    /// JSON-encoded `[PHD2Tool]` (raw values).
    var relatedPHD2ToolsData: Data = Data()

    var generatedAt: Date = Date()
    var dismissedAt: Date? = nil

    init() {}
}

/// Persistent user-recorded event tied to a night.
@Model
final class AnnotationEntity {
    var id: UUID = UUID()
    var rigProfileId: UUID = UUID()
    var nightRecord: NightRecordEntity? = nil

    var eventDate: Date = Date()
    /// JSON-encoded `Set<AnnotationCategory>` raw values.
    var categoriesData: Data = Data()
    var label: String = ""
    var detail: String = ""
    var isRigMutating: Bool = false

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init() {}
}

/// Persistent target cluster (Phase 8 pointing/target awareness).
@Model
final class TargetClusterEntity {
    var id: UUID = UUID()
    var rigProfile: RigProfileEntity? = nil

    var centerRA: Double = 0       // hours
    var centerDec: Double = 0      // degrees
    var radiusDeg: Double = 0.5

    var catalogMatch: String? = nil
    var sessionCount: Int = 0
    var totalIntegrationMinutes: Double = 0
    var medianRMSArcsec: Double = 0

    /// JSON-encoded `[UUID]`.
    var nightRecordIdsData: Data = Data()

    init() {}
}

/// Persistent Guiding Assistant result parsed from log INFO entries.
@Model
final class GAResultEntity {
    var id: UUID = UUID()
    var nightRecord: NightRecordEntity? = nil
    /// Denormalized — SwiftData / Core Data's SQL generator can't traverse two
    /// levels of optional relationships in a predicate, so we keep the rig id flat
    /// on the GA result for the @Query filter to use.
    var rigProfileId: UUID = UUID()

    var runAt: Date = Date()
    var durationSec: Int = 0
    var recommendedRAMinMovePx: Double? = nil
    var recommendedDecMinMovePx: Double? = nil
    var recommendedExposureSec: Double? = nil
    var polarAlignErrorArcmin: Double? = nil
    var decBacklashMs: Double? = nil
    var raPeakToPeakArcsec: Double? = nil
    var raMaxRateOfChangeArcsecPerSec: Double? = nil
    var highFreqStarMotionArcsecRMS: Double? = nil
    var recommendedBacklashCompensationMs: Int? = nil
    var rawText: String = ""

    init() {}
}

/// Annotation categories from design doc §9. Stored in `AnnotationEntity.categoriesData`
/// as a JSON-encoded `Set<String>` of raw values.
enum AnnotationCategory: String, Codable, CaseIterable, Sendable {
    case equipment
    case calibration
    case environment
    case software
    case freeText
}
