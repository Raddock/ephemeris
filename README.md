# Ephemeris

A Mac-native analyzer for PHD2 guide logs — single-night review and a multi-night library with plain-language recommendations.

Ephemeris is a Universal macOS app for astrophotographers who use [PHD2](https://openphdguiding.org) for autoguiding. Version 2 grows beyond a log viewer: import your whole log archive into a **Log Library**, see per-rig trends across nights, and get observations in plain language — "calibration is 34 days old", "Dec drift at this rate would trail stars on a 5-minute sub at your imaging scale" — each labeled with whether it comes from PHD2's own measurements or an Ephemeris heuristic.

## Status

- **Current release: 1.0** (May 2026) — the single-log analyzer, macOS 14+, available from [GitHub Releases](https://github.com/Raddock/ephemeris/releases/latest).
- **Version 2.0 is in active development on this branch (`v2`) and has not been released.** The Log Library section below describes the 2.0 work in progress; it will ship when it is finished.

<!-- TODO: add screenshots -->

## Features

### The Log Library (2.0, in development — unreleased)
- **Multi-night library** — bulk-import a folder of PHD2 logs (deduplicated by content, organized per rig) or let every log you open auto-ingest. The library is the app's home window.
- **Cross-night trend chart** — RMS per observing night, color-coded against your rig's imaging pixel scale.
- **Recommender observations** — 23 analysis rules spanning PHD2's documented guidance (calibration sanity alerts, Guiding Assistant results surfaced verbatim, max-duration rail-rates) and data-derived patterns (pier-side bias, cooldown signatures, star-shape prediction, baseline regression). Every card carries a source-authority badge, its evidence, and links to the PHD2 tools it references.
- **PHD2 hygiene strip** — days since last calibration, Guiding Assistant run, and polar-alignment measurement, at a glance.
- **Rig profiles** — your imaging train (focal length, pixel size, binning, reducer) anchors verdicts to *your* sky-sampling: sub-pixel / at-resolution / over-resolution.
- **Annotations & sub-quality ratings** — record equipment changes and rate each night's stars (round / elongated / trailed); a rating that contradicts the guide RMS triggers a differential-flexure suspicion.
- **Forum export** — one click builds a Markdown/BBCode help-request post with your rig, recent nights, and observations.
- **Claude integration (MCP)** — an opt-in, loopback-only, read-only MCP server (plus a bundled stdio helper with one-click Claude Desktop / Claude Code setup) lets an AI assistant analyze your library conversationally.
- **Shortcuts** — "Open most recent log" and "Show recent trends" from Shortcuts, Spotlight, or Siri.

### Single-log analysis (since 1.0)
- **Read PHD2 guide logs** with full support for both Mac- and Windows-generated files (CRLF and LF), AO devices, mount-only setups, and old-format px/ms rate logs.
- **Per-session statistics** — RMS RA, RMS Dec, total RMS, peak deviations, drift in arcsec/min, and König-method polar-alignment estimate.
- **Aggregate statistics** across the whole log — frame-count-weighted RMS, best and worst session indicators with one-click jump.
- **Time-series guide chart** with hover readout, click-to-pin selection, configurable Y scale, pixels or arc-seconds, RA/Dec or dx/dy axes, dragged-range zoom or exclusion.
- **Manual frame exclusions** — drag across the chart to remove cloud passes or noisy ranges from statistics.
- **Combined sessions** — multi-select consecutive sessions to view a whole night as a single chart, with real wall-clock gaps preserved.
- **Frequency analysis** — FFT-based periodogram for RA or Dec to surface worm-gear periodic error.
- **Calibration view** — square XY plot with concentric reference rings, leg rates, parity, and orthogonality readouts.
- **Export** — chart as PNG, session/frame/log-summary CSVs via the system share sheet.
- **Apple Help Book** — searchable in-app documentation covering the interface and the guiding concepts behind the analysis (expanded to 41 pages in the 2.0 work).
- **Universal binary** — runs natively on Apple silicon and Intel Macs.

## Requirements

- The released 1.0: macOS 14 (Sonoma) or later. The in-development 2.0: macOS 15 (Sequoia) or later (the library is built on APIs that require it).
- A PHD2 `.txt` guide log to open. PHD2 typically saves logs to `~/Documents/PHD2/` on Mac, or `Documents\PHD2\` on Windows.

## Installation

Download the `Ephemeris-x.y.zip` asset from the [GitHub Releases page](https://github.com/Raddock/ephemeris/releases/latest) (currently v1.0), unzip, and drag `Ephemeris.app` into your `Applications` folder. To try the in-development 2.0, build this branch from source in Xcode.

The app is signed with Developer ID and notarized by Apple — no Gatekeeper warnings on first launch. Starting with 2.0, Ephemeris will offer in-app updates via Sparkle (automatic checks only with your consent); 1.0 shipped without Sparkle, so 1.0 users update manually.

## Acknowledgments

This project is a Swift/SwiftUI rewrite of [phdlogview](https://github.com/agalasso/phdlogview) by Andy Galasso, originally implemented in C++ with wxWidgets. The original tool is the de facto standard log analyzer in the astrophotography community and informs this project's feature set, terminology, and core analysis workflow.

The PHD2 log file format itself is not formally documented; the C++ parser in [logparser.cpp](https://github.com/agalasso/phdlogview/blob/master/logparser.cpp) was used as the authoritative reference for the log structure, header conventions, and edge-case handling (non-monotonic timestamps, AO direction aliases, INFO coalescing). Statistical analysis (RMS, drift, FFT) was implemented independently using Apple's Accelerate framework, with different algorithm choices than the original.

See [CODE_PROVENANCE.md](docs/CODE_PROVENANCE.md) for the full provenance assessment.

## License

Released under the GNU General Public License v3.0. See [LICENSE.txt](LICENSE.txt) for the full text.

GPLv3 was chosen to match the upstream `phdlogview` project.

## Contributing

Pull requests are welcome. By submitting code, you agree that your contributions are licensed under GPLv3 to match the rest of the project.

For bug reports and feature requests, open an issue. If you've got a PHD2 log file that doesn't parse correctly, attaching it (or a redacted excerpt) to the issue is the fastest way to get it fixed.
