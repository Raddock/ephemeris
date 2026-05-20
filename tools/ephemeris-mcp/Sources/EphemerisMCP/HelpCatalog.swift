import Foundation

/// In-helper mirror of the app's HelpTopic catalog. Just enough to return a title
/// + one-paragraph summary for the `get_help_topic` MCP tool. The full help book
/// lives inside the .app bundle and is opened by the app via NSHelpManager; the
/// helper can't render HTML so it returns the title + summary text and lets the
/// MCP client decide what to do with it.
enum HelpCatalog {
    struct Topic: Sendable {
        let id: String
        let title: String
        let summary: String
    }

    static func topic(id: String) -> Topic? {
        all.first { $0.id == id }
    }

    static let all: [Topic] = [
        Topic(id: "reading-the-guide-log",
              title: "Reading your guide log",
              summary: "What each axis on the time-series chart represents, what 'included' vs 'excluded' frames mean, and how to navigate sessions inside a single log."),
        Topic(id: "pixel-scale-and-resolution",
              title: "Pixel scale and imaging resolution",
              summary: "How focal length, pixel size, binning, and any reducer combine into arcsec/px. The number that tells you whether guide RMS is hiding under your image sampling or showing up in your stars."),
        Topic(id: "image-scale-ratio",
              title: "The image-scale ratio and round stars",
              summary: "Why a 0.5″ guide RMS produces round stars on a 1.5″/px setup and slightly elongated stars on a 0.4″/px setup. The 'image-scale ratio' rule of thumb."),
        Topic(id: "what-the-guide-log-cant-tell-you",
              title: "What the guide log can't tell you",
              summary: "Seeing vs equipment. Flexure between the guider and the imager. Thermal cooldown of the OTA. Sub-quality you'd see by eye but never appear in PHD2's data."),
        Topic(id: "differential-flexure",
              title: "Differential flexure",
              summary: "The classic 'great guide RMS, trailed subs' signature. How OAG vs guidescope shifts the question, what to test, what helps."),
        Topic(id: "polar-alignment-fundamentals",
              title: "Polar-alignment fundamentals",
              summary: "Why polar alignment matters for unguided drift and for Dec polarity skew. Practical thresholds for sub-frame requirements and the trade-off with field rotation."),
        Topic(id: "calibration-orthogonality",
              title: "Calibration orthogonality",
              summary: "Why the angle between PHD2's measured RA and Dec legs should be near 90°, what large orthogonality errors imply about the mount/setup, and when to recalibrate."),
        Topic(id: "calibration-staleness",
              title: "When to recalibrate",
              summary: "How often calibration genuinely needs to be redone. Mount/encoder type vs gear-mount differences. When the Calibration Assistant is worth the extra five minutes."),
        Topic(id: "guiding-assistant",
              title: "The Guiding Assistant",
              summary: "What GA measures, how to read its recommendations, why PHD2's measured min-move beats heuristic guesses, and how to run it well at the start of a session."),
        Topic(id: "calibration-troubleshooting",
              title: "Calibration troubleshooting",
              summary: "PHD2's four named calibration sanity alerts (Too Few Steps, Orthogonality, Questionable Rates, Inconsistent Results) and what each one is actually telling you."),
        Topic(id: "guide-algorithms",
              title: "Guide algorithms — when defaults are right",
              summary: "Hysteresis vs ResistSwitch vs LowPass2 vs PredictivePEC. PHD2's documented recommendation per mount class, and when deviating from defaults is sensible."),
        Topic(id: "aggressiveness-and-min-move",
              title: "Aggressiveness, min-move, exposure",
              summary: "The three knobs that shape PHD2's response to seeing-induced motion. Why min-move from the Guiding Assistant beats min-move you guessed at."),
        Topic(id: "max-duration-limits",
              title: "Max RA / Dec duration",
              summary: "What PHD2's max-pulse setting protects you from (runaway corrections) and what saturating it costs you (missed real motion). When to widen the cap and when not to."),
        Topic(id: "backlash-and-uni-directional",
              title: "Backlash and uni-directional guiding",
              summary: "Why backlash compensation works on some mounts and fails on others. When uni-directional Dec guiding is the right answer."),
        Topic(id: "common-patterns",
              title: "Common patterns",
              summary: "Oscillation, drift, settling overshoot, periodic worm signatures — what they look like in PHD2's chart, and what they typically mean."),
        Topic(id: "optical-train-health",
              title: "Optical-train health",
              summary: "Tilt, collimation, focus, dew, mirror flop. How each one shows up in star shape rather than guide RMS, and how to test for it without guessing."),
        Topic(id: "pre-flight-checklist",
              title: "Pre-flight checklist",
              summary: "What to verify before you start imaging: cooldown, focus, polar alignment, calibration age, GA freshness. The five-minute test that prevents most lost nights."),
        Topic(id: "asking-for-help-well",
              title: "When to ask for help and how",
              summary: "What information to gather, what the guide log alone can answer, and what's worth asking the community vs working through alone. Includes the forum-export workflow."),
        Topic(id: "variable-exposure-delays",
              title: "Variable Exposure Delays",
              summary: "What VED does, why encoder-based premium mounts specifically benefit, and how to configure it in PHD2's Brain → Camera tab."),
        Topic(id: "multi-star-guiding",
              title: "Multi-star guiding",
              summary: "How multi-star mode averages across guide stars to suppress single-star seeing noise. Why the design doc recommends it as the default for most setups."),
        Topic(id: "seeing-vs-equipment",
              title: "Seeing vs equipment — telling them apart",
              summary: "Three-guard rule: star-mass coefficient of variation, altitude/airmass, and absolute RMS together. Why one signal in isolation can't separate the two."),
    ]
}
