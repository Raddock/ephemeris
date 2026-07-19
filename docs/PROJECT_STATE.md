# Ephemeris — Project State (v2)

> Generated from commit 751e29a at version 2.0 / build 1, 2026-07-19.

<!-- sidecar:facts:begin -->
> **Measured at `751e29a` (`v2`), 2026-07-19:** 91 Swift files in the app target `Ephemeris/`; 17,044 lines of Swift; 23 test files.
<!-- sidecar:facts:end -->

*Snapshot for design / strategy reference. Generated from the codebase on the `v2` branch and not from memory; Sidecar stamps the sync-key header ("Generated from commit...") when it first regenerates this file. **`v2` is the live, unfinished development branch: everything below describes the current state of the 2.0 work in progress, and none of it has shipped.** The only released version is 1.0 (see `CHANGELOG.md` and `RELEASE_NOTES.md`); deferred work lives in `ROADMAP.md`. Note the branch topology, established from git during the July 2026 conform pass so it is not re-discovered later: **`main` itself is unreleased 2.0 work in progress**, carrying 54 commits past the v1.0 tag (the Phase 0-9 feature build, from 2026-05-18); only the final polish (28 commits, June-July 2026) lives on `v2`. When 2.0 ships, "releases are cut from `main`" (`RELEASE.md`) therefore means: finish and merge `v2`, and the release cut includes all post-1.0 work on `main`, none of which has shipped anywhere yet. For an outside reader: this is an open-source (GPLv3) project, and this document plus the README are the honest picture of where it stands. Supersedes the v1 snapshot; see `docs/ephemeris-2.0-design-document.md` for the design the v2 build followed.*

## 1. Summary

Ephemeris is a native macOS app for astrophotographers built around PHD2 guide logs. Version 1 was a single-log viewer — open a `.txt` log, get a sidebar of sessions, a time-series chart, calibration plots, statistics rollups, an FFT periodogram, and CSV/PNG export. Version 2 keeps all of that and grows the app into a long-term guiding intelligence tool:

- **A persistent Log Library** (SwiftData) that ingests every log you open or bulk-import, organized per rig, with a cross-night trend chart, a PHD2 hygiene strip (calibration / Guiding Assistant / polar-alignment freshness), and a Recent Nights table.
- **A recommender engine** — 19 single-night and 4 cross-night rule generators that turn raw stats into plain-language observations ("calibration is 34 days old", "Dec drift would trail stars on a 5-minute sub at your imaging scale"), each tagged with a source authority (PHD2 manual / PHD2 measurement / heuristic) that controls how assertive the wording is.
- **Rig profiles** — equipment metadata (imaging train, guide train, mount class) keyed to the immutable PHD2 profile name from the log, with a user-editable display name. The imaging pixel scale anchors star-shape prediction and RMS verdict colors.
- **An embedded MCP server** — a loopback-only HTTP listener inside the app exposing read-only library tools to Claude (plus a bundled stdio helper binary with a one-click Claude Desktop / Claude Code installer).
- **Annotations and sub-quality feedback** — user-recorded events (equipment changes, environment notes) and per-night star-shape verdicts that feed back into the recommender (e.g. "you rated this night trailed but guiding was sub-pixel — suspect differential flexure").
- **App Intents** — "Open most recent log" and "Show recent trends" exposed to Shortcuts / Spotlight / Siri.

It remains a reimplementation lineage of `agalasso/phdlogview` (GPLv3); see `CODE_PROVENANCE.md`.

## 2. Tech stack

- **macOS deployment target:** 15.0 (Sequoia).
- **Swift version:** 5.0 toolchain with Swift 6 concurrency idioms (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, explicitly `nonisolated` parser/model/stat types, a `ModelActor` ingestor).
- **UI framework:** SwiftUI throughout; AppKit interop only for window-subtitle override, `NSOpenPanel` flows (bulk import, installer), and `ImageRenderer` export.
- **Persistence:** SwiftData (`SchemaV1`, 7 entities), store at `~/Library/Application Support/Ephemeris/Library.store` (inside the sandbox container). A `SchemaMigrationPlan` (`LibraryMigrationPlan`, empty stages for now) is registered on the ModelContainer so future schema versions migrate in place. No CloudKit sync, but the schema is CloudKit-clean (no unique attributes, optional relationships, defaults).
- **Charts:** Swift Charts (guide chart, calibration plot, scatter inset, FFT, library trend chart).
- **Math:** Accelerate (vDSP real FFT) for the periodogram; straight Swift elsewhere.
- **Networking:** Network.framework (`NWListener`) for the embedded MCP HTTP server, loopback-only.
- **Other Apple frameworks:** TipKit (library-discovery tip), App Intents, Core Spotlight (night-record indexing), UniformTypeIdentifiers.
- **Third-party packages:** Sparkle 2.x (SPM) for auto-update — the only external dependency. The stdio MCP helper under `tools/ephemeris-mcp/` is a separate SPM executable package bundled into `Ephemeris.app/Contents/Helpers/` (built universal + timestamp-signed by the bundling phase).
- **Sandbox / entitlements:** app-sandboxed; `files.user-selected.read-write` plus `network.server` (for the loopback MCP listener). Security-scoped folder bookmarks (`SourceFolderBookmarks`) persist access to log folders.
- **Build system:** Xcode 26.x project, `objectVersion = 77`, file-system-synchronized groups.
- **License:** GPLv3 (`LICENSE.txt`, `CODE_PROVENANCE.md`).

## 3. Architecture overview

Layered by convention, not enforcement:

**Parsing layer (`Parser/`).** `GuideLogParser.parse(_:)` — the v1 five-state machine over log lines — plus `HeaderParser`, `CalibrationHeaderParser`, `InfoCoalescer`, `NonMonotonicFix`, and `PHD2LogSignature` (head-of-file classification that rejects non-PHD2 / binary input before parsing). `Persistence/GAResultParser.swift` additionally extracts PHD2 Guiding Assistant "GA Result" INFO lines into structured records during ingest.

**Model layer (`Model/`).** Plain `Sendable` value types. The v1 set (`GuideLog`, `GuideSession`, `GuideEntry`, `Calibration`, …) plus v2 domain types: `RigProfile` (+ `MountClass`, `GuideConfiguration`, `ImagingScale`), `RecommenderObservation` (scope / category / severity / confidence / evidence / source authority), `Annotation`, `SubQualityVerdict`, `SourceAuthority`, `PHD2Tool`, `PHD2Algorithm`.

**Stats layer (`Stats/`).** Unchanged in spirit from v1: pure functions, no caching. `SessionStatsCalculator`, `LogAggregateStats`, `FrequencyAnalyzer`, `GuideSessionMerger`, `CSVExporter`.

**Recommender layer (`Recommender/`).** `RecommenderEngine` is stateless; it runs an array of `SingleNightGenerator`s over a `SingleNightContext` (log + rig profile + per-session stats) and `CrossNightGenerator`s over a `CrossNightContext` (the rig's `NightRecordEntity` corpus). Supporting pure logic lives beside it: `StarShapePredictor`, `TargetClustering`, `Astronomy` (galactic latitude, alt/az, hour angle), `SessionHeaderProperties`, `HelpTopic`.

**Persistence layer (`Persistence/`).** `EphemerisLibrary` (ModelContainer facade, in-memory mode for tests), `SchemaV1` (the 7 `@Model` entities), `LibraryIngestor` (a `ModelActor` running the idempotent ingest pipeline), `LibraryBulkImporter` + `ImportCoordinator` (folder import), `SourceFolderBookmarks`, `ForumPostExporter`, `GAResultParser`, `CoreSpotlightIndexer`, `ClaudeConfigInstaller`.

**MCP layer (`MCPServer/`).** `MCPEmbeddedServer` (NWListener on 127.0.0.1, dynamic port persisted in UserDefaults, status state machine), `MCPConnectionHandler` (HTTP request handling, origin hardening), `MCPProtocolHandler` (JSON-RPC), `MCPTools` (tool registry reading the library).

**View layer (`Views/`).** SwiftUI views; per-window UI state in `@State`, persisted chart preferences in `ChartViewState` (`@Observable`, UserDefaults-backed). All guide charts (guide graph, diagnostic graph, scatter inset) render cached decimated models (`GuideChartData`) rather than raw entries, so a 200k-frame night stays fluid; the FFT sheet caches its spectrum per input key. New v2 surfaces are described in §5.

**Data flow.** Opening a document parses it (as in v1) *and* auto-ingests it into the library: parse → night stats → pointing context → recommender → upsert. Bulk import drives the same ingest per file. Library views query SwiftData directly; observations are recomputed on every ingest so threshold changes propagate without re-import.

## 4. Data model

### Value types (per-document, v1 heritage)

`GuideLog` / `SectionRef` / `GuideSession` / `GuideDevice` / `GuideEntry` / `InfoEntry` / `InfoKind` / `Calibration` / `CalibrationDetails` / `LegCompletion` / `CalibrationEntry` / `SessionStats` / `LogAggregateStats` / `FrequencySpectrum` — unchanged in shape from v1 (see git history of this file for the field-level detail), except `GuideSession`, which gained `malformedFieldCount` (unreadable-but-present fields, counted per session and surfaced as a damaged-data banner in the inspector).

### v2 domain value types

- **`RigProfile`** — imaging train (focal length, pixel size, binning, reducer), guide train (configuration, camera, focal length), mount (class, model, high-precision-encoders flag), notes. `currentName` is the immutable PHD2 profile name parsed from the log; `displayName` is the user-facing override. Computed imaging/guide pixel scales via `ImagingScale`.
- **`RecommenderObservation`** — scope (`singleNight`/`crossNight`), category (subQuality → opticalTrain → equipment → phd2Hygiene → pattern → suggestion, which is also the triage order), severity (alert → coaching), confidence, `SourceAuthority`, title/summary/suggestedResponse, evidence items, candidate contributors, related `PHD2Tool`s and `HelpTopic`s.
- **`SourceAuthority`** — `phd2Manual` / `phd2Measurement` / `phd2BehaviorDocumented` / `communityConsensus` / `ephemerisHeuristic`; carries a badge label and a "soften the voice" flag.
- **`Annotation`** — categories (equipment / calibration / environment / software / free text), short label, detail, `isRigMutating` flag, event date.
- **`SubQualityVerdict`** — user's imaging verdict for a night: round / slightlyElongated / trailed / mixed.
- **`PHD2Tool`** — enum of 14 PHD2 tools with canonical names and manual URLs (powers the hygiene strip and observation links).

### SwiftData entities (`Persistence/SchemaV1.swift`)

- **`RigProfileEntity`** — mirror of `RigProfile` + timestamps; relationships to night records and target clusters. The single owner of rig-profile data: `RigProfileStore` reads and writes this entity directly. (The v1 JSON sidecar under Application Support/Ephemeris/Profiles/ is imported once on first launch, then the folder is parked as `Profiles.migrated-backup`.)
- **`NightRecordEntity`** — one ingested log/night: source file path + SHA-256 content hash (idempotency key), night date, session count, integration minutes, night/best/worst RMS (arcsec; the per-night rollup is a frame-weighted quadrature mean, surfaced everywhere as "night RMS" and kept in the legacy median-named attribute until SchemaV2), serialized per-session stats and calibration data, `subQualityRaw`, pointing context (circular-median RA, Dec, galactic latitude, Messier catalog match), ingest timestamps; relationships to observations, annotations, GA results, session records.
- **`SessionRecordEntity`** — per-session detail: stats (RMS/peak/drift/polar-align in arcsec), frame counts, pixel scale, pointing (RA/Dec/hour angle/alt/az/pier side), HFD, exposure, multi-star flag.
- **`ObservationEntity`** — persisted recommender output (enums stored raw, evidence/contributors/help-topics as JSON), `dismissedAt` for user dismissal.
- **`AnnotationEntity`** — persisted `Annotation`.
- **`TargetClusterEntity`** — pointing-proximity cluster: center RA/Dec, radius, catalog match, session count, integration, median RMS, member night IDs.
- **`GAResultEntity`** — one Guiding Assistant run: recommended min-moves, exposure, polar-align error, Dec backlash, RA peak-to-peak and max rate of change, high-frequency star motion, raw text. (Runs that report only a max rate of change are still persisted.)

## 5. Surfaces and scenes

`EphemerisApp` declares seven scenes:

1. **`DocumentGroup`** (read-only `GuideLogDocument` → `ContentView`) — the v1 single-log viewer, lightly enhanced: observation cards in the inspector, auto-ingest on open, commands for Log Library (⇧⌘L), Rig Profiles, MCP Server, Import Folder.
2. **`WindowGroup` "Log Library"** (`id: library`, 980×720, `.defaultLaunchBehavior(.presented)`) — the app now launches into the library, not an open panel. NavigationSplitView: rig sidebar → detail with date-range picker (Week/Month/Year/Custom/All; presets anchor to the rig's most recent ingested night, so the header reads "week ending <date>"), trend chart (dragging across it zooms into that period by switching to a custom range), hygiene strip, active-observations panel (collapsible behind a remembered header disclosure; RA/Dec pairs of the same finding merge into one title-only card via `ObservationPairMerger`, with per-axis sections when expanded; storage and MCP stay per-axis), Recent Nights table (verdict-tinted RMS, predicted star shape, sub-quality rating, annotations; double-click reopens the source log via bookmarks). Empty states distinguish "no nights in this range" from "no nights ingested at all". Rig deletion via context menu or ⌘⌫.
3. **`Window` "Rig Profiles"** (`id: rigProfiles`, 720×540) — rig list + full profile editor (imaging/guide train, mount class, display name, notes), with guide-train auto-fill from the PHD2 log header and a header-hint button.
4. **`Window` "MCP Server"** (`id: mcpServer`, 640×620) — server status/port, connection stats, restart, one-click Claude Desktop / Claude Code installers, manual-config fallback display.
5. **`Window` "Importing PHD2 logs"** (`id: library-import`, 600×460) — bulk-import progress. A standalone window rather than a sheet (sheets were collapsing under this OS version).
6. **`Window` "About Ephemeris"** — custom About panel (v1 heritage).
7. **`Settings`** — flat single-pane app settings, including a library-reset action (open library windows refresh after a reset).

Plus the Apple Help Book (⌘?) and the frequency-analysis sheet from v1.

## 6. The recommender engine

`RecommenderEngine` registers **19 single-night generators** in three authority tiers, and **4 cross-night generators** run during ingest against the rig's corpus. Output is sorted by category then severity; heuristic-tier findings use softened, non-imperative voice per the design's voice rules.

**PHD2-canon tier** (`Generators/PHD2CanonGenerators.swift`): GuidingAssistantRecommendation (surfaces PHD2's own GA measurements/recommendations verbatim), CalibrationSanityAlert, MaxDurationLimit, CalibrationStaleness (pattern at 21d, alert at 30d), CalibrationOrthogonality (pattern > 5°, alert > 10°), VariableExposureDelays, MultiStarGuiding, AlgorithmMismatch.

**Heuristic tier** (`Generators/HeuristicGenerators.swift`): DecPolarityBias, AtmosphericConditionsProxy.

**Gap-analysis tier** (`Generators/GapAnalysisObservers.swift`, closing the matrix in `docs/observation-gap-analysis.md`): StarShapePrediction, PierSideBias, CooldownSignature, MinMoveValidation, GuideRateValidation, Aggressiveness, DataDrivenAlgorithmHint, GuideScaleMismatch, StarLost.

**Cross-night** (`Generators/CrossNightGenerators.swift`): CalibrationAngleShift (≈10° step change = rig-mutation signature; suppressed by a rig-mutating annotation), GAFreshness, BaselineRegression (recent median RMS vs the corpus p90; needs ≥10 nights), SubQualityDiscrepancy (user verdict contradicts guide RMS → flexure suspicion).

**`StarShapePredictor`** is a pure function from night RMS, drift, per-session spread, and the *imaging* pixel scale (not the guide scale — all call paths feed the same RMS input) to round(±bloated) / slightlyElongated / trailed(cause) / mixed / unknown. Its verdict maps onto `SubQualityVerdict` for the predicted-vs-rated comparison shown in Recent Nights.

**Baselines:** per-rig percentiles (p75/p90) over night RMS drive relative verdicts (`NightVerdict` tiers tint the trend chart and tables); when an imaging scale is configured, absolute sub-pixel/at-resolution tiers are used instead.

## 7. MCP server

Two transports, one data source (the SwiftData library):

**Embedded (primary).** `MCPEmbeddedServer` runs inside the app — Network.framework listener bound to 127.0.0.1 only, dynamic port persisted across launches, JSON-RPC over HTTP POST. Hardened against browser cross-origin probing and malformed input (a supplied-but-invalid `rig_id` is an error, not a fall-through to "all rigs"; `list_nights` date/limit are bound as SQL parameters; requests are capped at 1 MB with strict Content-Length validation, answered with 400/413 instead of buffering forever). Five read-only tools: `list_rigs`, `list_nights`, `list_observations`, `get_aggregate_stats`, `get_corpus_summary`. The per-night rollup is exposed as `night_rms_arcsec` in both catalogs (true across-nights medians keep their `median` names). Source-authority labels survive into tool output so an AI consumer can distinguish PHD2-measured facts from Ephemeris heuristics.

**Stdio helper (for clients that can't speak HTTP).** `tools/ephemeris-mcp/` — a separate SPM executable bundled into `Ephemeris.app/Contents/Helpers/`, reading the library store directly (read-only SQLite). Same read-only tool surface as the embedded server, and strictly read-only: the former opt-in `add_annotation` write tool, its raw-SQLite write path, and the `EPHEMERIS_MCP_ALLOW_WRITES` env gate were all removed, and the helper package's own test target asserts catalog parity plus the no-writes guarantee. `ClaudeConfigInstaller` does the one-click setup: NSOpenPanel grant → JSON-merge of the `ephemeris` entry into the Claude Desktop / Claude Code config, idempotent and atomic, keeping a `.bak` copy of the pre-install config and writing no env block; its hardcoded dev-path fallback for the helper binary is DEBUG-only.

## 8. Persistence and ingest

`LibraryIngestor` (ModelActor) pipeline, idempotent on the log's SHA-256: parse → frame-weighted night RMS in arcsec (handles mixed-pixel-scale logs) → pointing context (circular-median RA with wrap handling, galactic latitude, ±0.5° Messier match) → run recommender, upsert observations → create per-session records → parse and persist GA results. The real source path is stored (not a bare filename) so "open original log" works; `SourceFolderBookmarks` resolves a covering security-scoped bookmark (correct path-prefix matching at component boundaries) or prompts once per new folder. Bulk import matches each log's PHD2 profile name to an existing rig or auto-creates one, enforces the same 500 MB per-file cap as document open, and recreates its ingest `ModelActor` every 25 files to bound memory. Log decoding falls back to Latin-1 when UTF-8 fails (document open, signature check, and bulk import alike). The ModelContainer is created with `LibraryMigrationPlan` (see §2) so schema changes ship as staged migrations. Rig profiles live in the same store: `RigProfileStore` is SwiftData-backed with `RigProfileEntity` as the single owner, and the old JSON sidecar is one-time-imported then parked (see §4).

## 9. PHD2 log format handling

Unchanged from v1 (five-state machine, quote-aware 18/19-column tokenizer, signed W/S durations, AO step overwrite, px/ms heuristic, INFO coalescing, non-monotonic-timestamp repair, `PHD2LogSignature` front gate, 500 MB hard refusal) — plus v2 additions: Guiding Assistant result extraction matches PHD2's real "GA Result" line shapes, session header properties (RA/Dec/hour angle/alt/az/pier side/HFD/exposure/multi-star) are extracted for pointing awareness, and unreadable-but-present fields are counted per session (`GuideSession.malformedFieldCount`, zero on healthy logs) instead of silently dropped, feeding the inspector's damaged-data banner. The parser and value-model layer are explicitly `nonisolated` (Swift 6 clean).

## 10. Known limitations and rough edges

*Items here are live constraints of the current build. Deferred feature work
lives in `docs/ROADMAP.md`; a few small items appear in both because they are
simultaneously a limitation and planned work.*

*(The June 2026 pre-release hardening pass fixed the earlier list: dead recommender
paths matched against invented log formats, the sourceFilePath clobber, rig-profile
dual-store drift on edit/delete, sandbox-broken "open original log", concurrent
bulk imports, MCP transport divergence (reducer factor, field shapes), contradictory
verdict tiers, midnight-split trend nights, the help book's missing pages and wrong
book ID, MARKETING_VERSION, and the helper's single-arch/no-timestamp signing.
The July 2026 audit pass then fixed: uncached per-render chart analysis (guide
charts and the FFT now render cached decimated models), the stdio helper's write
path (now strictly read-only), the "median RMS" misnomer for the per-night rollup
(now "night RMS"), JSON-sidecar rig profiles (now SwiftData-owned), and embedded
MCP request hardening; it also shipped the first full accessibility pass over
charts, icon buttons, and combined rows.)*

- **Sparkle is live as of 2026-07-07** — the EdDSA keypair exists (private key in
  the signing Mac's login Keychain, public key in Info.plist). Each release still
  needs an `appcast.xml` asset (see docs/RELEASE.md). Automatic checks stay
  consent-gated.
- **Not localized** — ~120 user-facing strings are
  hardcoded English; no String Catalog exists (decision and scheduling: `ROADMAP.md`). Deferred: costs
  nothing while English-only, but budget a mostly mechanical multi-day retrofit
  before any international push.
- **Embedded MCP server has no auth token** — now opt-in (off by default, choice
  persisted), loopback-only, read-only; but while running, any local process can
  read library summaries. A per-session token would close that.
- **UI tests are minimal** (launch smoke test only). The library/import/MCP windows
  have no UI-level coverage; unit coverage is strong (see §11).
- **Predictive PEC (GP) algorithm settings** span multiple header lines, so its
  aggression/min-move aren't attributable to an axis by the header parser.
- **`hourAngleHours` / `pierSide`** calibration-side values still surface only in
  the inspector.
- **100 MB "may take a while" confirmation** still deferred, tracked in `ROADMAP.md` (only the 500 MB
  refusal shipped).
- **Legacy `.appiconset` + `.icon` package dual-maintenance** and the post-CodeSign
  icon copy phase (v1 carryovers).
- **Re-imports re-run the full analysis on dedup hits** — by design (threshold
  changes propagate without re-import), but it means re-importing a big unchanged
  folder pays full parse cost. An analysis-fingerprint skip is the future fix.

## 11. Build, run, test

**Build:**
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Ephemeris.xcodeproj -scheme Ephemeris build
```

**Tests:** `xcodebuild … test`. The unit suite covers: parser + signature + calibration headers (including malformed-field counting), session/aggregate stats, FFT, merger, CSV, rig profiles and the SwiftData-backed store, annotations, the recommender engine (single-night and cross-night generators, threshold boundaries), observation pair merging, chart decimation (`GuideChartData`), the embedded MCP server (request hardening, malformed input), library ingest idempotency, and a corpus-validation pass that parses every bundled real log and asserts the recommender fires (skips gracefully when the corpus folder is absent). The stdio helper package has its own test target (`tools/ephemeris-mcp/Tests/`) asserting catalog parity with the embedded server and the read-only guarantee.

**Sample data:** `EphemerisTests/Fixtures/` small fixture log; corpus tests look for an optional local folder of real logs (not committed).

## 12. File map (compact)

```
Ephemeris/
  Parser/          GuideLogParser, HeaderParser, CalibrationHeaderParser,
                   InfoCoalescer, NonMonotonicFix, PHD2LogSignature
  Model/           GuideLog, GuideSession, Calibration, RigProfile, RigProfileStore,
                   MountClass, GuideConfiguration, ImagingScale, RecommenderObservation,
                   Annotation, SubQualityVerdict, SourceAuthority, PHD2Tool, PHD2Algorithm
  Stats/           SessionStats(+Calculator), LogAggregateStats, FrequencyAnalyzer,
                   GuideSessionMerger, CSVExporter
  Recommender/     RecommenderEngine, SingleNightContext, CrossNightContext,
                   StarShapePredictor, TargetClustering, Astronomy,
                   SessionHeaderProperties, HelpTopic, ObservationPairMerger
    Generators/    PHD2CanonGenerators (8), HeuristicGenerators (2),
                   GapAnalysisObservers (9), CrossNightGenerators (4)
  Persistence/     EphemerisLibrary, SchemaV1 (7 @Model entities),
                   LibraryMigrationPlan, LibraryIngestor,
                   LibraryBulkImporter, ImportCoordinator, SourceFolderBookmarks,
                   GAResultParser, ForumPostExporter, CoreSpotlightIndexer,
                   ClaudeConfigInstaller
  MCPServer/       MCPEmbeddedServer, MCPConnectionHandler, MCPProtocolHandler, MCPTools
  AppIntents/      EphemerisAppIntents (OpenMostRecentLog, ShowRecentTrends,
                   EphemerisRigEntity), MostRecentLogResolver, AppShortcutBridge
  Document/        GuideLogDocument
  Views/           ContentView, EphemerisApp, LibraryWindow, TrendChartView,
                   PHD2HygieneStrip, NightVerdict, ObservationCard, AnnotationSheet,
                   SubQualityPicker, ImagingScaleVerdictChip, LibraryImportSheet,
                   LibraryDiscoveryTip, RigProfilesWindow, RigProfileEditorView,
                   RigProfileConfigureSheet, MCPServerWindow, SettingsWindow,
                   ForumExportSheet, GuideChartData (cached decimated chart models),
                   ChartPalette, + the v1 chart/inspector/export views

tools/ephemeris-mcp/   SPM stdio MCP helper (bundled into Contents/Helpers/);
                       Tests/ = catalog-parity + read-only-guarantee tests

docs/
  PROJECT_STATE.md                   This file — current state of the app
  ROADMAP.md                         Decided-but-deferred future work (the only
                                     forward-looking doc; delete items as they ship)
  RELEASE.md                         Release checklist (Sparkle, notarize, appcast)
  CODE_PROVENANCE.md                 GPL lineage analysis vs phdlogview (permanent)
  ephemeris-2.0-design-document.md   The v2 design this build followed (historical,
                                     all phases shipped)
  observation-gap-analysis.md        Signature → PHD2-lever coverage map (all v2
                                     gaps closed; debug-log rows deferred)
  archive/                           Point-in-time reports, all findings resolved
                                     (April ultrareview, July 2026 code audit)

EphemerisTests/    Unit tests (parser + malformed fields, stats, recommender,
                   cross-night, pair merging, chart decimation, embedded MCP,
                   ingest, rig profiles, annotations, corpus validation)
EphemerisUITests/  Launch smoke test

README.md / LICENSE.txt (root)
```
