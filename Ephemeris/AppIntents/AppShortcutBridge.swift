import AppKit
import Foundation

/// Bridges App Intent notifications (`.ephemerisShowTrends`, `.ephemerisOpenRecentLog`)
/// to scene actions. The intents themselves can't talk to SwiftUI's @Environment
/// directly, so they post a NotificationCenter event and this bridge translates
/// it into an `openWindow` + selection update.
///
/// We use UserDefaults as the cross-scene handoff so the LibraryWindow can read
/// the pending rig selection on next open without a global state object.
@MainActor
final class AppShortcutBridge {
    static let shared = AppShortcutBridge()

    private var registered = false

    func registerOnce() {
        guard !registered else { return }
        registered = true

        NotificationCenter.default.addObserver(
            forName: .ephemerisShowTrends,
            object: nil,
            queue: .main
        ) { note in
            let rigId = (note.userInfo?["rigId"] as? String) ?? ""
            UserDefaults.standard.set(rigId, forKey: "shortcut.pending.libraryRigId")
            // Window opens via NSApp's services menu in the receiver; falling back
            // to NSWorkspace.shared.open ensures we activate even if no window is open.
            NSApp.activate(ignoringOtherApps: true)
            // Post a follow-up that the LibraryWindow reads in onReceive — see LibraryWindow.
            NotificationCenter.default.post(name: .ephemerisOpenLibraryWindow, object: nil)
        }

        NotificationCenter.default.addObserver(
            forName: .ephemerisOpenRecentLog,
            object: nil,
            queue: .main
        ) { note in
            let rigId = note.userInfo?["rigId"] as? String
            NSApp.activate(ignoringOtherApps: true)
            // Resolve the latest night's source-file path for this rig via the
            // library reader, then open it through SourceFolderBookmarks so the
            // sandbox scope is reacquired.
            Task { @MainActor in
                guard let path = MostRecentLogResolver.resolve(rigUUID: rigId) else { return }
                _ = SourceFolderBookmarks.openLog(at: path)
            }
        }
    }
}

extension Notification.Name {
    /// Posted by the bridge when an App Shortcut wants the Library window to open.
    /// `EphemerisApp` doesn't open the window directly (no `openWindow` env outside
    /// the SwiftUI body), so the `LibraryWindow` listens and toggles its own state.
    static let ephemerisOpenLibraryWindow = Notification.Name("com.macobservatory.Ephemeris.openLibraryWindow")
}
