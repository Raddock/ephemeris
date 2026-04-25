# Ephemeris

A Mac-native viewer and analyzer for PHD2 guide logs.

Ephemeris is a Universal macOS app for astrophotographers who use [PHD2](https://openphdguiding.org) for autoguiding. Open a log file from a night of imaging and review every guiding and calibration section in a Mac-native interface — RMS, drift, frequency analysis, multi-session merging, scatter cluster, and CSV exports — without needing Rosetta, wxWidgets, or any external dependencies.

<!-- TODO: add screenshots -->

## Features

- **Read PHD2 guide logs** with full support for both Mac- and Windows-generated files (CRLF and LF), AO devices, mount-only setups, and old-format px/ms rate logs.
- **Per-session statistics** — RMS RA, RMS Dec, total RMS, peak deviations, drift in arcsec/min, and König-method polar-alignment estimate.
- **Aggregate statistics** across the whole log — frame-count-weighted RMS, best and worst session indicators with one-click jump.
- **Time-series guide chart** with hover readout, click-to-pin selection, configurable Y scale (Auto, ±0.5″, ±1″, ±2″, ±5″, ±10″), pixels or arc-seconds, RA/Dec or dx/dy axes, dragged-range zoom or exclusion.
- **Manual frame exclusions** — drag across the chart to remove cloud passes or noisy ranges from statistics.
- **Combined sessions** — multi-select consecutive sessions in the sidebar to view a whole night as a single chart, with real wall-clock gaps preserved.
- **Frequency analysis** — FFT-based periodogram for RA or Dec to surface worm-gear periodic error.
- **Calibration view** — square XY plot with concentric reference rings, leg rates, parity, and orthogonality readouts.
- **Scatter cluster overlay** showing the wandering pattern of guide deviations.
- **Diagnostic sub-charts** for star mass and SNR.
- **Export** — chart as PNG, session/frame/log-summary CSVs via the system share sheet (sandbox-safe; no special entitlements).
- **Apple Help Book** — full searchable in-app documentation via macOS Help Viewer.
- **Universal binary** — runs natively on Apple silicon and Intel Macs.

## Requirements

- macOS 14 (Sonoma) or later.
- A PHD2 `.txt` guide log to open. PHD2 typically saves logs to `~/Documents/PHD2/` on Mac, or `Documents\PHD2\` on Windows.

## Installation

<!-- TODO: download link once first release is tagged -->

## Acknowledgments

This project is a Swift/SwiftUI rewrite of [phdlogview](https://github.com/agalasso/phdlogview) by Andy Galasso, originally implemented in C++ with wxWidgets. The original tool is the de facto standard log analyzer in the astrophotography community and informs this project's feature set, terminology, and core analysis workflow.

The PHD2 log file format itself is not formally documented; the C++ parser in [logparser.cpp](https://github.com/agalasso/phdlogview/blob/master/logparser.cpp) was used as the authoritative reference for the log structure, header conventions, and edge-case handling (non-monotonic timestamps, AO direction aliases, INFO coalescing). Statistical analysis (RMS, drift, FFT) was implemented independently using Apple's Accelerate framework, with different algorithm choices than the original.

See [CODE_PROVENANCE.md](CODE_PROVENANCE.md) for the full provenance assessment.

## License

Released under the GNU General Public License v3.0. See [LICENSE.txt](LICENSE.txt) for the full text.

GPLv3 was chosen to match the upstream `phdlogview` project.

## Contributing

Pull requests are welcome. By submitting code, you agree that your contributions are licensed under GPLv3 to match the rest of the project.

For bug reports and feature requests, open an issue. If you've got a PHD2 log file that doesn't parse correctly, attaching it (or a redacted excerpt) to the issue is the fastest way to get it fixed.
