# Ephemeris release notes

> User-facing "what's new" per released version, newest first. This is the announcement copy of record (GitHub Releases; Sparkle release notes once 2.0 ships). Per the documentation standard this is a Draft doc: Sidecar drafts, the owner tone-checks before anything reaches users. Ephemeris has one release to date.

## 2.0 — 2026-07-31

*Distribution note: 1.0 shipped without Sparkle, so 1.0 users will not see an update prompt; the 2.0 announcement must reach them through GitHub, the website, and forums.*

Ephemeris 2.0 grows beyond a single-log viewer. Import your whole PHD2 log archive into a Log Library: nights are deduplicated, organized per rig, and charted across time. A recommender with 25 analysis rules turns your guiding data into plain-language observations ("calibration is 34 days old", "Dec drift at this rate would trail stars on a 5-minute sub at your imaging scale"), each labeled with whether it comes from PHD2's documentation, PHD2's own measurements, or an Ephemeris heuristic. Rig profiles anchor every verdict to your imaging scale. Record equipment changes and rate each night's stars; build a forum help-request post in one click; let Claude analyze your library through an opt-in, loopback-only, read-only MCP server. Adds Shortcuts support, a 39-page Help Book, and in-app updates via Sparkle going forward. Requires macOS 15 (Sequoia).

## 1.0 — 2026-05-01

The first release: a Mac-native analyzer for PHD2 guide logs. Open a night's log and see every guiding and calibration session in a native interface: RMS and drift statistics, an interactive guide chart with zoom and frame exclusion, combined consecutive sessions, an FFT periodogram for periodic error, a calibration plot with orthogonality readouts, star mass and SNR diagnostics, and CSV/PNG export. Includes a searchable Apple Help Book. Universal binary, Developer ID signed and notarized. macOS 14 (Sonoma) or later. Free and open source under GPLv3, as a Mac-native successor to phdlogview.
