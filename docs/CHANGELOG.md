# Changelog — Ephemeris

> Per-version record, newest first. Created during the July 2026 documentation-standard conform pass from git history and the v1.0 tag.

## 2.0.4 (build 5), unreleased

Point release from `main`: the recommender stops misreading lost-star stretches and ASIAir logs.

- **Recommender: lost-star stretches no longer feed diagnoses.** New `LostStar` finds sessions that end with the guide star moving steadily away from the lock position and never returning inside PHD2's search region (with guiding output on). `SingleNightContext` gives generators the night with those stretches cut (sessions with under 10 frames left are dropped); `rawLog` keeps the log as parsed for the star-shape observation (so it matches the Library chip) and the Guiding Assistant observation (PHD2's results verbatim). On a customer's ASIAir nights it finds 11 of 180 sessions, all runaways; on the owner's NINA corpus 1 of 710.
- **New observation "Guiding lost the star"** (Ephemeris heuristic): what was measured (distance, length, unmeasured frames, corrections on each axis), what it usually means, and what would tell the causes apart.
- **"Elevated RMS, likely atmospheric"** stays silent above 5″ RMS and needs half a guide pixel to call RMS elevated (ASIAir nights: 31 to 4; owner corpus: 179 to 172).
- **Cooldown** ignores sessions under 30 included frames (the ASIAir "81× worse" first session was 3 frames).
- **ASIAir logs:** `GuideLog.isASIAir`; "Multi-star guiding not enabled" no longer fires on them (the ASIAir never writes the field); advice naming PHD2 dialogs or tools carries a note that ASIAir settings live in its app.
- Codex review, four rounds: ten findings accepted (Int.min duration magnitude, Guiding Assistant stretches and results, corrections on both axes, single-spike robustness, length through unmeasured frames, non-finite distances, calibration sanity alerts from the uncut log, corrupt timestamps, merged sessions declined because they carry only the first session's header), each with a test in `LostStarTests`. Help: Observations and Seeing vs equipment pages. Record: `docs/decisions/2026-11-17-lost-star-and-asiair-advice.md`.

## 2.0.3, 2026-11-17 (tag `v2.0.3`, build 4)

Point release from `main` for ASIAir users, released 2026-11-17 (Developer ID signed, notarized, Sparkle appcast with deltas from 2.0, 2.0.1, and 2.0.2, each verified with `BinaryDelta apply` to rebuild the signed app byte for byte): one crash fix found by the post-release Codex review of 2.0.2. Before shipping, the customer's 11 ASIAir logs were re-verified end to end (import, re-import, single-log open, recommender, Autorun recognition).

- **Corrupt focal length no longer crashes ASIAir rig matching** (found by the post-release Codex review of 2.0.2). `RigIdentity` formatted the guide focal length with `Int(_:)`, which traps above `Int.max`; a blank-profile header with a huge or overflowing `Focal length` value crashed the app on open or bulk import. Values outside 0 to 100,000 mm now read as missing, so the log has no rig key instead. Real ASIAir logs write ordinary focal lengths, so no shipped user is known to be affected.

## 2.0.2, 2026-11-17 (tag `v2.0.2`, build 3)

Point release from `main`, released 2026-11-17 (Developer ID signed, notarized, Sparkle appcast with deltas from 2.0 and 2.0.1 on the GitHub release): ASIAir logs import into the Library, night RMS becomes a frame-weighted median, and the Library reset crash is fixed.


- **ASIAir logs import into the Library.** The ASIAir writes `Equipment Profile = ` with no name, and both Library paths keyed rigs on that name, so bulk import rejected every ASIAir log ("no `Equipment Profile = …` line in header") and opening one never ingested it or showed the recommender. New `RigIdentity` is the one place a log becomes a rig key: the PHD2 profile name when present, otherwise (profile line present but blank) `ASIAir · <camera> · <focal length> mm · <mount>` from the same header. The bulk importer, document window, session detail, and inspector all use it. Rig editor and inspector copy say "ASIAir guide train" for these rigs. Verified on a customer's folder: 11 of 11 guide logs imported, 0 errors, one rig per guide setup (5).
- **ASIAir Autorun logs named on open.** `PHD2LogSignature` returns `.asiAirAutorunLog` for the ASIAir's `Autorun_Log_*.txt` (the `[Autorun|` marker, checked only after every PHD2 marker fails), and the open error points to the `PHD2_GuideLog_` file from the same night instead of the generic "not a PHD2 guide log".
- `ASIAirFormatTests` adds rig-key cases (blank vs named vs missing profile, mount change) and an end-to-end bulk import of two synthetic ASIAir nights into one rig. Help pages Bulk import and Rig profiles explain ASIAir rig naming.
- Decision record: `docs/decisions/2026-11-16-asiair-rig-identity.md`.
- **Night RMS is now the frame-weighted median of session RMS** (owner decision). The old frame-weighted quadrature mean let a few minutes of runaway guiding swamp a night: one ASIAir night read 107″ when most of its guiding was under 1″ (now 0.79″). `NightRMS.frameWeightedMedian` is shared by the ingestor and the single-night recommender (whose evidence row now says "Night RMS"). On the owner's 56 nights, 40 move less than 20% and 15 drop by more. Stored nights update on re-import. The stored attribute `medianRMSArcsec` is now accurately named, so the SchemaV2 rename is dropped from ROADMAP. A per-night failed-attempt count was considered and deferred (settle status misfires on NINA logs). Record: `docs/decisions/2026-11-16-night-rms-median.md`.
- **Reset Log Library no longer crashes with the Library window open** (bug present in 2.0 and 2.0.1). The reset used `ModelContext.delete(model:)`, a store-level batch delete that bypasses the context: the window's `@Query` kept its night objects, still registered and apparently live, and the next redraw trapped reading a deleted `SessionRecordEntity` (`StarShapePredictor.predict`, from the night row's predicted-shape chip). `EphemerisLibrary.resetLibraryData()` now deletes object by object on the main context, which detaches each object so the queries drop it. `LibraryResetTests` holds a night across the reset, as the open window does.

## 2.0.1 — 2026-10-23 (tag `v2.0.1`, build 2)

Point release for ASIAir guide logs, merged from `v2` to `main` and released 2026-10-23 (Developer ID signed, notarized, Sparkle appcast with a 2.0 to 2.0.1 delta on the GitHub release).

- **ASIAir banner recognized.** ASIAir writes `PHD2 version, Log version 2.5` with no version number. The signature check and the version parser share a new `PHD2LogSignature.isBanner`, so these logs classify as `.confirmed` (they previously passed only as `.likely`) and keep their log version.
- **Pointing line without RA.** ASIAir omits `RA = ` from the pointing line, and `SessionHeaderProperties` matched Dec, hour angle, and pier side in one regex anchored on RA, so all three were lost. They are now matched on their own; RA is read only when present.
- `ASIAirFormatTests` covers both with a synthetic log in the ASIAir layout, plus regressions for full PHD2 pointing lines and for other `Dec =` fields.
- Reported by a user whose ASIAir log would not open. That log already parsed in 2.0, so the error they saw is still unexplained.

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
