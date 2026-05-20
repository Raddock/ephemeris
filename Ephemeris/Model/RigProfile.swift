import Foundation

/// Per-PHD2-profile equipment metadata. Stable identifier across rename and reconfiguration.
///
/// v2.0 ships this as a pure value type with JSON-sidecar persistence (Phase 1).
/// Phase 3 promotes it to a SwiftData `@Model` with the same field shape. The CloudKit-clean
/// rules from design doc §4 (defaults everywhere, optional relationships, ordered-array-as-Data)
/// already apply here so the Phase 3 migration is mechanical.
struct RigProfile: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    /// **Immutable identity** — the PHD2 `Equipment Profile = X` value from the log.
    /// This is the foreign key that matches logs to rigs; never edit it in the UI.
    /// `nameHistory` covers the case where PHD2 itself renames the profile over time.
    var currentName: String
    var nameHistory: [String]
    /// **User-facing label** — freely editable. Surfaced in the sidebar, chart titles,
    /// and headers. When empty, the UI falls back to `currentName`.
    var displayName: String?

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
        displayName: String? = nil,
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
        self.displayName = displayName
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
    nonisolated var imagingPixelScale: Double {
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

    /// The label to show users — `displayName` when set, falls back to the PHD2 profile name.
    var effectiveName: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        return currentName
    }

    /// **Advanced / repair operation** — change the PHD2 profile name (the matching key).
    /// Used only when an existing rig was created with the wrong identity (e.g., the user
    /// typed a name before this app enforced log-derived identity). The previous name is
    /// preserved in `nameHistory` so historically-matched logs still resolve.
    mutating func repairPhd2Name(to newName: String) {
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
