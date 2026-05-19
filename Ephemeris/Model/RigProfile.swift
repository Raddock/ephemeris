import Foundation

/// Per-PHD2-profile equipment metadata. Stable identifier across rename and reconfiguration.
///
/// v2.0 ships this as a pure value type with JSON-sidecar persistence (Phase 1).
/// Phase 3 promotes it to a SwiftData `@Model` with the same field shape. The CloudKit-clean
/// rules from design doc §4 (defaults everywhere, optional relationships, ordered-array-as-Data)
/// already apply here so the Phase 3 migration is mechanical.
struct RigProfile: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var currentName: String
    var nameHistory: [String]

    var imagingFocalLength: Double   // mm
    var imagingPixelSize: Double     // μm
    var imagingBinning: Int          // 1, 2, 3, …
    var reducerFactor: Double?       // multiplier; 1.0 or nil = none

    var guideConfiguration: GuideConfiguration
    var guideCameraPixelSize: Double // μm
    var guideFocalLength: Double     // mm (the guide-train focal length)
    var guideBinning: Int

    var mountModel: String?
    var mountClass: MountClass
    var hasHighPrecisionEncoders: Bool

    var typicalSubExposure: Int?     // seconds
    var notes: String?

    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        currentName: String = "",
        nameHistory: [String] = [],
        imagingFocalLength: Double = 0,
        imagingPixelSize: Double = 0,
        imagingBinning: Int = 1,
        reducerFactor: Double? = nil,
        guideConfiguration: GuideConfiguration = .oag,
        guideCameraPixelSize: Double = 0,
        guideFocalLength: Double = 0,
        guideBinning: Int = 1,
        mountModel: String? = nil,
        mountClass: MountClass = .standardGearMount,
        hasHighPrecisionEncoders: Bool = false,
        typicalSubExposure: Int? = nil,
        notes: String? = nil,
        createdAt: Date = .now,
        modifiedAt: Date = .now
    ) {
        self.id = id
        self.currentName = currentName
        self.nameHistory = nameHistory
        self.imagingFocalLength = imagingFocalLength
        self.imagingPixelSize = imagingPixelSize
        self.imagingBinning = imagingBinning
        self.reducerFactor = reducerFactor
        self.guideConfiguration = guideConfiguration
        self.guideCameraPixelSize = guideCameraPixelSize
        self.guideFocalLength = guideFocalLength
        self.guideBinning = guideBinning
        self.mountModel = mountModel
        self.mountClass = mountClass
        self.hasHighPrecisionEncoders = hasHighPrecisionEncoders
        self.typicalSubExposure = typicalSubExposure
        self.notes = notes
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Cached imaging pixel scale in arcsec/px. Computed from focal length, pixel size, binning, reducer.
    /// Returns 0 when the inputs are insufficient (treated as "unconfigured").
    var imagingPixelScale: Double {
        ImagingScale.compute(
            focalLengthMm: imagingFocalLength,
            pixelSizeMicrons: imagingPixelSize,
            binning: imagingBinning,
            reducerFactor: reducerFactor
        )
    }

    /// Guide-train pixel scale in arcsec/px. Same formula as imaging.
    /// When `guideConfiguration == .sameOptics`, falls back to the imaging scale.
    var guidePixelScale: Double {
        if guideConfiguration == .sameOptics {
            return imagingPixelScale
        }
        return ImagingScale.compute(
            focalLengthMm: guideFocalLength,
            pixelSizeMicrons: guideCameraPixelSize,
            binning: guideBinning,
            reducerFactor: nil
        )
    }

    /// True when imaging scale has enough inputs to compute meaningfully.
    var isImagingScaleConfigured: Bool {
        imagingFocalLength > 0 && imagingPixelSize > 0 && imagingBinning > 0
    }

    /// Apply a rename, preserving prior name in history.
    public mutating func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentName else { return }
        if !currentName.isEmpty && !nameHistory.contains(currentName) {
            nameHistory.append(currentName)
        }
        currentName = trimmed
        modifiedAt = .now
    }

    /// True if this profile matches the given PHD2 profile name — either current or historical.
    func matches(profileName: String) -> Bool {
        let target = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }
        return currentName == target || nameHistory.contains(target)
    }
}

/// How the guide camera is mounted relative to the imaging optics.
/// Drives flexure observations (guide-scope) and informs calibration cadence advice.
enum GuideConfiguration: String, Codable, CaseIterable, Sendable {
    case oag         = "Off-axis guider"
    case guideScope  = "Separate guide scope"
    case sameOptics  = "Same optics (no separate guider)"
}
