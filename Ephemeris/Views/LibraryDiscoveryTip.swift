import SwiftUI
import TipKit

/// Per design doc §7.1: when the third NightRecord lands, show a tip recommending
/// the user open the Library window. Replaces the auto-open behavior the design
/// rejected (HIG: don't open windows on the user's behalf).
///
/// Implementation note: macOS 15 TipKit's `@Parameter` propertyWrapper has shaky
/// support — we use a plain UserDefaults-backed counter and a manual `invalidate()`
/// call to control display rather than parameter-rule plumbing.
struct LibraryDiscoveryTip: Tip {
    var title: Text {
        Text("Your library is filling up")
    }
    var message: Text? {
        Text("Open **Window → Library** (⇧⌘L) to see trends across nights, RMS distribution, and cross-night observations.")
    }
    var image: Image? {
        Image(systemName: "books.vertical")
    }
}

@MainActor
enum LibraryDiscoveryTipBootstrap {
    private static let ingestedKey = "library.discovery.ingestedCount"
    private static let shownKey = "library.discovery.tipShown"

    static func configure() {
        do {
            try Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault),
            ])
        } catch {
            NSLog("[Tips] configure failed: %@", "\(error)")
        }
    }

    /// Called after a successful new NightRecord ingest. Increments the persistent
    /// counter; when the threshold is crossed, marks the tip as eligible.
    static func recordIngestedNight() {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: ingestedKey) + 1
        defaults.set(count, forKey: ingestedKey)
        if count == 3 && !defaults.bool(forKey: shownKey) {
            defaults.set(true, forKey: shownKey)
            // The tip's eligibility is now true; the menu-bar attachment will pick
            // it up the next time the user opens the application menu.
        }
    }

    /// Whether the tip should be shown on this launch. Used to gate the
    /// `.popoverTip` modifier in the toolbar menu attachment.
    static var shouldShowTip: Bool {
        let defaults = UserDefaults.standard
        return defaults.integer(forKey: ingestedKey) >= 3 &&
               !defaults.bool(forKey: "library.discovery.tipDismissed")
    }

    static func dismissTip() {
        UserDefaults.standard.set(true, forKey: "library.discovery.tipDismissed")
    }

    /// Called when the user resets the Log Library — the counter mirrors library
    /// contents, so an emptied library must start over or the tip points at nothing.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: ingestedKey)
        UserDefaults.standard.removeObject(forKey: shownKey)
    }
}
