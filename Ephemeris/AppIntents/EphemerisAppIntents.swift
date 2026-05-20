import AppIntents
import AppKit
import Foundation
import SwiftData

/// Phase 6 deliverable per design §10: surface common Ephemeris workflows as
/// macOS App Shortcuts so users can invoke them from Shortcuts.app, Spotlight,
/// the menu bar's Shortcuts menu, and Siri.
///
/// Shipped:
///   - "Open most recent log for [rig]" — opens the latest `.txt` log Ephemeris
///     has ingested for the chosen rig (resolves the night's `sourceFilePath` and
///     hands it to NSWorkspace; SourceFolderBookmarks restores the security scope).
///   - "Show this week's trends for [rig]" — opens the Library window pre-filtered
///     to the chosen rig + Week range.
///
/// Both intents post on a shared NotificationCenter channel that EphemerisApp
/// listens to. The user never sees the notification — it's an internal handoff
/// from the AppIntent task to the SwiftUI scene.

// MARK: - Notifications wired into EphemerisApp

extension Notification.Name {
    /// Posted by `ShowRecentTrendsIntent`. UserInfo: `["rigId": String?]`.
    static let ephemerisShowTrends = Notification.Name("com.macobservatory.Ephemeris.showTrends")
    /// Posted by `OpenMostRecentLogIntent`. UserInfo: `["rigId": String?]`.
    static let ephemerisOpenRecentLog = Notification.Name("com.macobservatory.Ephemeris.openRecentLog")
}

// MARK: - Rig AppEntity

/// AppEntity representation of a rig profile so users can pick "which rig" from
/// the Shortcuts app picker. Backed by the JSON-sidecar `RigProfileStore` (Phase 1).
struct EphemerisRigEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Rig")

    static var defaultQuery = EphemerisRigQuery()

    let id: UUID
    let currentName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(currentName)")
    }
}

struct EphemerisRigQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [EphemerisRigEntity] {
        let store = RigProfileStore()
        return store.profiles
            .filter { identifiers.contains($0.id) }
            .map { EphemerisRigEntity(id: $0.id, currentName: $0.effectiveName) }
    }

    @MainActor
    func suggestedEntities() async throws -> [EphemerisRigEntity] {
        let store = RigProfileStore()
        return store.profiles.map {
            EphemerisRigEntity(id: $0.id, currentName: $0.effectiveName)
        }
    }
}

// MARK: - Open most recent log

struct OpenMostRecentLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Open most recent log"
    static let description = IntentDescription(
        "Opens the most recent PHD2 guide log Ephemeris has ingested for the chosen rig.",
        categoryName: "Logs"
    )
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Rig", description: "Which rig's most recent log to open")
    var rig: EphemerisRigEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .ephemerisOpenRecentLog,
            object: nil,
            userInfo: ["rigId": rig?.id.uuidString as Any]
        )
        return .result(dialog: "Opening the most recent log…")
    }
}

// MARK: - Show recent trends

struct ShowRecentTrendsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show recent trends"
    static let description = IntentDescription(
        "Opens the Log Library window pre-filtered to the chosen rig and the most recent week.",
        categoryName: "Log Library"
    )
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Rig", description: "Which rig's trends to show")
    var rig: EphemerisRigEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .ephemerisShowTrends,
            object: nil,
            userInfo: ["rigId": rig?.id.uuidString as Any]
        )
        return .result(dialog: "Showing recent trends…")
    }
}

// MARK: - Shortcuts catalog

struct EphemerisShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenMostRecentLogIntent(),
            phrases: [
                "Open the most recent \(.applicationName) log",
                "Open most recent log in \(.applicationName)",
            ],
            shortTitle: "Open Most Recent Log",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: ShowRecentTrendsIntent(),
            phrases: [
                "Show \(.applicationName) trends",
                "Show recent \(.applicationName) trends",
            ],
            shortTitle: "Show Recent Trends",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
    }
}
