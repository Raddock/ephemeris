# Changelog — Ephemeris

> Per-version record, newest first. Created during the July 2026 documentation-standard conform pass from git history and the v1.0 tag.

## 2.0 — 2026-07-31 (tag `v2.0`)

Version 2 grows the single-log viewer into a long-term guiding intelligence tool. Released 2026-07-31 from `main` (Developer ID signed, notarized, Sparkle appcast on the GitHub release). The recommender shipped with 21 single-night and 4 cross-night generators after the July 31 forum-triage additions.

### The Log Library and recommender (v2 Phases 0–9, on `main` after the v1.0 tag, 2026-05-18 onward)
- Persistent SwiftData **Log Library** (SchemaV1, 7 entities): every opened log auto-ingests; bulk folder import with content-hash deduplication, organized per rig; the library is the app's home window.
- **Recommender engine**: 19 single-night and 4 cross-night rule generators producing plain-language observations, each tagged with a source authority (PHD2 manual / PHD2 measurement / Ephemeris heuristic) that controls how assertive the wording is.
- **Rig profiles** keyed to the PHD2 profile name; imaging pixel scale anchors star-shape prediction and RMS verdicts.
- **Annotations and sub-quality ratings** feeding back into the recommender (differential-flexure suspicion when a rating contradicts guide RMS).
- **Cross-night trend chart**, PHD2 hygiene strip, forum export (Markdown/BBCode).
- **MCP integration**: embedded loopback-only read-only server plus the bundled stdio helper with one-click Claude Desktop / Claude Code setup.
- **App Intents**: "Open most recent log" and "Show recent trends."
- v2 Help Book (41 pages).

### Pre-release hardening and Sparkle (2026-06-10)
- Tier 1–4 hardening passes: dead recommender paths vs real PHD2 formats, data-integrity fixes in the library layer, MCP parity/security, UX, release mechanics, performance.
- Sparkle 2 auto-update integrated (design Phase 0, deferred until now); kept dormant in test hosts and unconfigured builds.
- Range-appropriate empty state for the observations panel.

### July 2026 code-audit pass (2026-07-07)
- Embedded MCP HTTP handling hardened (invalid `rig_id` errors instead of falling through; bound SQL parameters; 1 MB request cap).
- Stdio MCP helper made **strictly read-only**: the `add_annotation` write tool, its write path, and the `EPHEMERIS_MCP_ALLOW_WRITES` gate removed; a test asserts catalog parity and the no-writes guarantee.
- "Night RMS" rename across user-facing surfaces (the value is a frame-weighted quadrature mean, not a median; the stored attribute keeps its legacy name until SchemaV2).
- Guide charts downsampled and cached off the render path; FFT moved off the render path; Latin-1 fallback for non-UTF-8 logs; parser-coerced fields counted per session.
- SwiftData single owner for rig profiles; `LibraryMigrationPlan` (empty stages) registered so future schema changes migrate in place.
- Bulk-import memory capped with a huge-file guard; config installer backs up before writing and ships no dev paths in release builds.
- First accessibility pass; library ranges anchored with drag-to-zoom on the trend chart; observations panel tidied (merged RA/Dec pairs, disclosure grouping); canonical pbxproj ordering.
- Real Sparkle EdDSA public key shipped in Info.plist.

### Concurrency and documentation (2026-07-08 to 2026-07-11)
- Parser and log value-model layers made explicitly `nonisolated` (the app defaults to MainActor isolation).
- Documentation pass to the current build; docs reorganized into current state (`PROJECT_STATE.md`) vs roadmap (`ROADMAP.md`) vs removed archive files.

## [1.0] — 2026-05-01

Initial public release: a Mac-native, single-log PHD2 guide-log analyzer. Public history began 2026-04-25 with the GPLv3 compliance pass; Developer ID signed and notarized; distributed as `Ephemeris-1.0.zip` via GitHub Releases. macOS 14 (Sonoma) or later, Universal binary. Shipped without Sparkle (1.0 users update manually).

- PHD2 guide-log parsing: Mac and Windows files (CRLF/LF), AO devices, mount-only setups, old-format px/ms rate logs.
- Per-session statistics: RMS RA/Dec/total, peak deviations, drift in arcsec/min, König-method polar-alignment estimate.
- Aggregate statistics: frame-count-weighted RMS, best/worst session indicators with one-click jump.
- Time-series guide chart: hover readout, click-to-pin, Y scales (Auto, ±0.5″ to ±10″), pixels or arc-seconds, RA/Dec or dx/dy, drag zoom and exclusion.
- Manual frame exclusions; combined consecutive sessions with wall-clock gaps preserved.
- FFT periodogram (RA/Dec) for worm-gear periodic error; calibration view (square XY plot, reference rings, leg rates, parity, orthogonality); scatter cluster overlay; star mass and SNR sub-charts.
- Export: chart PNG plus session/frame/log-summary CSVs via the share sheet (sandbox-safe).
- Apple Help Book; Universal binary.
