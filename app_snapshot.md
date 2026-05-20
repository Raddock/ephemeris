# Ephemeris

A Mac-native viewer and analyzer for PHD2 guide logs.

## Status & distribution

- **Status:** Pre-1.0. Public source on GitHub since 2026-04-25; pre-launch hardening pass complete; no release tagged yet.
- **Distribution:** Self-distributed via GitHub (open-source). No App Store, no TestFlight.
- **Pricing:** Free, GPL-3.0.
- **Brand accent:** TBD — `AccentColor` is currently the system default; pick before first release.

## Target user & problem

Astrophotographers who use [PHD2](https://openphdguiding.org) for autoguiding and want a Mac-native way to review the night's guide log. The reference viewer (`agalasso/phdlogview`) is C++/wxWidgets, requires Rosetta on Apple silicon, and feels foreign on macOS. Ephemeris reads the same `.txt` log and surfaces the same data — RMS, drift, FFT, calibration plots — in a native SwiftUI app.

## Key features

- Per-session time-series chart with RA/Dec lines, hover/pin readouts, drag-to-zoom or drag-to-exclude, fixed and auto Y-scale.
- Aggregate summary across the whole log: weighted RMS, best/worst session chips, sortable session table with per-row quality bars.
- Multi-select sidebar to combine consecutive sessions (with real wall-clock gaps preserved) into one stitched view.
- FFT periodogram for periodic-error analysis; calibration XY plot with reference rings and orthogonality readout.
- Bordered-card inspector showing every parsed metadata field; click events to jump the chart to that frame.
- Export: chart as PNG, session/frame/aggregate CSV via the system share sheet.
- In-app Apple Help Book with hero landing page, search index, and dark-mode CSS.

## Tech stack

- macOS 14+, Swift 5, SwiftUI throughout. AppKit only at two seams (window-subtitle override, `NSImage` for PNG export).
- Apple Charts for every chart; Accelerate (`vDSP_fft_zripD`) for the FFT.
- `DocumentGroup` + `FileDocument`, with a custom `PHD2LogSignature` head-of-file classifier as the gatekeeper.
- No SPM dependencies, no third-party SDKs.
- Liquid Glass app icon (Icon Composer `.icon`) for macOS 26, `.appiconset` fallback for 14/15.

## Scope boundaries

- **Not a guide controller.** Ephemeris reads PHD2 log files after the fact; it does not connect to mounts, cameras, or PHD2 itself. Guiding still happens in PHD2.
- Reads the guide log only. The PHD2 debug log is not parsed.
- One log per window. No cross-night comparison or library view.
- Log files are read-only — never written.

## External dependencies

None. Apple frameworks only.

## Public links

- **Source:** https://github.com/Raddock/ephemeris
- **Issues / support:** https://github.com/Raddock/ephemeris/issues
- **TestFlight / App Store / website:** N/A

## Current state & next milestones

- Pre-launch hardening complete (file-loading gate, sentinel discriminator from `/ultrareview`, frame-jump scroll, About panel link). 70 unit tests passing. Custom About panel, Liquid Glass icon, and Apple Help Book shipped.
- **Next:** tag v1.0, pick a brand accent, draft README screenshots, decide whether to add a TestFlight track.

## Open questions / known limitations

- 100 MB file-size confirmation prompt deferred (would need lifting document loading out of `DocumentGroup`); 500 MB hard refusal ships today.
- No analysis caching — `SessionStats` recomputes per render.
- No cross-night trend or comparison UI.
- Polar-align estimate is a single-session approximation; no quality warning when the drift fit is short or noisy.
