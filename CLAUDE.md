# CLAUDE.md — Ephemeris

Guidance for Claude Code working in the Ephemeris repository.

> **Codex auto-review:** After completing a feature or meaningful chunk of work, run a Codex review of the actual changes (`/codex:review`, or `/codex:adversarial-review` for performance-sensitive paths). Codex's findings must be critically evaluated, not rubber-stamped. Full procedure lives in the home-folder `~/.claude/CLAUDE.md`.

## What this is

Ephemeris is a Mac-native analyzer for PHD2 guide logs: single-night review plus (since 2.0) a multi-night SwiftData Log Library with a plain-language recommender. It is a Mac Observatory app, but unlike the others it is **public, open source (GPLv3)**: this is the suite's only public repo, so READMEs and top-level docs are read by strangers evaluating or contributing to the project, and everything committed here is visible to the world.

**Branch state:** two shipped releases: **v1.0** (tag `v1.0`, 2026-05-01) and **v2.0** (tag `v2.0`, 2026-07-31). The v2-to-main merge happened for the 2.0 ship; as of 2026-08-01 `main` and `v2` point at the same commit, and new work lands on whichever branch the owner designates next. Releases are cut from `main` per `docs/RELEASE.md`.

## Platform

- macOS 15.0 deployment target (2.0; 1.0 shipped on 14.0). Universal binary (Apple silicon + Intel).
- SwiftUI throughout; AppKit interop only where SwiftUI cannot express the need. SwiftData persistence. Swift Charts. Accelerate for FFT.
- `SWIFT_VERSION = 5.0` with Swift 6 concurrency idioms: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; parser, model, stats, and log-value layers are explicitly `nonisolated`; the library ingestor is a `ModelActor`; recommender generators are `nonisolated struct`s.
- Sandboxed, Developer ID distribution via GitHub Releases (`Raddock/ephemeris`); not on the Mac App Store, and never going there, by the owner's channel choice for the suite's open-source app. (Do not cite license conflict as the reason: `docs/CODE_PROVENANCE.md` records that GPLv3 is App Store compatible for the developer's own apps.) Sparkle 2 for updates.
- **Ephemeris does not use the Mac Observatory suite design system** (`~/Developer/MacObservatory/DESIGN_SYSTEM.md` is not referenced here, and no suite accent is defined). Follow this app's own established look and the HIG; do not import suite tokens without the owner's direction.

## Commands

```sh
# Build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Ephemeris.xcodeproj -scheme Ephemeris build

# App tests
xcodebuild -project Ephemeris.xcodeproj -scheme Ephemeris test

# MCP stdio helper tests
cd tools/ephemeris-mcp && swift test
```

The corpus-validation suite skips gracefully if the private log corpus folder is absent, so a clean clone still tests green.

## Invariants (do not violate without the owner's direction)

- **GPLv3 and provenance.** The whole app is GPLv3, matching upstream `agalasso/phdlogview`. The parser subsystem is a behavioral reimplementation of `logparser.cpp` and is the license-exposed area; keep everything GPLv3, and never attempt a permissive-license rewrite that consults `logparser.cpp`. Contributions are accepted only under GPLv3 (README § Contributing). Full analysis: `docs/CODE_PROVENANCE.md`.
- **Schema migrations only.** SwiftData `SchemaV1` (7 entities) with `LibraryMigrationPlan` registered on the container. Any schema change ships as a staged migration, never an in-place edit. Known trap: the per-night rollup is a frame-weighted quadrature mean surfaced everywhere as "night RMS", but the stored attribute keeps its legacy median name until SchemaV2 (queued in `ROADMAP.md`); do not "fix" the attribute name without the migration.
- **MCP stays read-only.** Both transports (the embedded loopback-only HTTP server and the stdio helper) expose read-only tools. The old `add_annotation` write tool and its `EPHEMERIS_MCP_ALLOW_WRITES` gate were deliberately removed in July 2026 (raw writes into the live store risk corruption); a test asserts the no-writes guarantee. If a write channel ever returns, it must be app-mediated (see `ROADMAP.md`), never direct database access. Since the 2026-07-31 ChatGPT-connector work the embedded server requires a bearer token on `/mcp` by default (generated on first use, persisted; the user can toggle it off); do not remove or weaken that gate.
- **Sparkle.** `SUEnableAutomaticChecks` is deliberately absent from Info.plist (setting it to either value suppresses Sparkle's consent prompt; absent, Sparkle asks the user on second launch and stores their choice). Never add it. The sandboxed install depends on `SUEnableInstallerLauncherService` plus the `-spks`/`-spki` mach-lookup entitlements. The updater stays dormant in test hosts and unconfigured builds. The private EdDSA key lives in the signing Mac's Keychain (see `docs/RELEASE.md`).
- **Recommender voice.** The twelve throughlines in `docs/ephemeris-2.0-design-document.md` §2 are the design invariants; treat them as the most stable layer. In copy: coaching voice, never imperative; don't overclaim causation (what was measured / what it could mean / what would disambiguate); every observation carries its source-authority badge; Guiding Assistant results are surfaced verbatim (PHD2's numbers, not parallel computations); PHD2 tool names are proper nouns capitalized exactly as PHD2's manual.
- **The Library window is never auto-opened.** Window-spawning is reserved for explicit user action; discovery is via TipKit.
- **Rejected for 2.0** (don't reach for these): on-device Foundation Models LLM, QuickLook thumbnail extension, UserNotifications, CoreML/CreateML, WeatherKit/MapKit.

## Gotchas

- Parser: 500 MB hard refusal (the 100 MB "may take a while" confirm is deferred, see ROADMAP); Latin-1 fallback when UTF-8 fails; malformed fields are counted per session (`GuideSession.malformedFieldCount`), never silently dropped.
- Re-importing an unchanged folder re-runs full analysis on dedup hits by design (so threshold changes propagate); the fingerprint-skip optimization is a queued ROADMAP item.
- Dual icon assets (`.appiconset` + `.icon`) must be maintained together, with the post-CodeSign icon copy phase.
- Not localized: ~120 hardcoded English strings, no String Catalog, deliberately deferred (ROADMAP).
- Writing style (suite-wide): no em dashes or en dashes, no business jargon, in prose, comments, commit messages, and user-facing copy.

## Documentation

| File | Purpose |
|------|---------|
| `docs/README.md` | The Mac Observatory documentation standard: canonical doc set, Auto/Draft/Manual policies, lifecycle. Read before adding or hunting for a document |
| `docs/PROJECT_STATE.md` | Generated current-state snapshot of the v2 build |
| `docs/ROADMAP.md` | Decided-but-deferred work; items deleted when shipped |
| `docs/CHANGELOG.md` | Per-version record: v1.0 and v2.0 shipped |
| `docs/RELEASE_NOTES.md` | User-facing what's-new per released version |
| `docs/RELEASE.md` | The release checklist (Sparkle keys, appcast, notarization, help index) |
| `docs/FEEDBACK.md` | Triaged feedback ledger; intake is GitHub issues (public repo) |
| `docs/ephemeris-2.0-design-document.md` | The v2 design spec: vision, twelve throughlines, build phases |
| `docs/observation-gap-analysis.md` | Recommender coverage matrix (signal, PHD2 lever, coverage) |
| `docs/CODE_PROVENANCE.md` | GPLv3 derivation analysis vs phdlogview (frozen, with dated addenda) |
| `docs/decisions/` | Dated decision records (changelog-is-manual, number-tokenizer-gap, store-status-staleness, all 2026-07-28; release-staleness-key, 2026-08-01) |

## Documentation ownership (church and state)

Per the standard (docs/README.md): every doc has exactly one owner; owners never write into each other's files.

- **Sidecar-owned**, regenerated from code: never hand-edit once the doc carries a "Generated from commit..." header: docs/CODEBASE_OVERVIEW.md, docs/PROJECT_STATE.md, docs/README.md, and docs/RELEASE_NOTES.md / docs/APP_STORE_RELEASE_NOTES.md (Draft: Sidecar proposes, Andrew approves). README.md is Sidecar-owned with marked draft:begin/end human regions, the one deliberate exception.
- **Claude Code-owned**, derived from conversation; Sidecar never writes these: docs/CHANGELOG.md (Manual by owner decision 2026-07-28, recorded in docs/decisions/2026-07-28-changelog-is-manual.md; release sessions write it with the change, Sidecar reads and cites only), CLAUDE.md, docs/ROADMAP.md, docs/FEEDBACK.md and docs/FEEDBACK_HISTORY.md, docs/decisions/, docs/RELEASE.md.
- **Frozen**, nobody writes: docs/archive/.

Until a doc carries the header it is hand-maintained, whatever its eventual owner. Sidecar knows what the code says; Claude Code knows what the conversation said: a fact that cannot be produced by a command does not belong in a Sidecar-owned doc.


## After a version bump

When you bump `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`, run the Sidecar
refresh afterward so the docs catch up the same day (the nightly run is the
backstop, not the plan):

```sh
node ~/Developer/MacObservatory/Sidecar/generator/sidecar-generate.mjs refresh ephemeris
```

It reports which Sidecar-owned docs need regeneration; complete them per its
output (or hand the report to a Sidecar session).
