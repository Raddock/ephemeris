# Ephemeris Roadmap

*The single home for feature ideas that are decided-but-deferred. Everything
here is future work; the current state of the app lives in `PROJECT_STATE.md`.
When an item ships, delete it from this file. Sources: design doc §11 (out of
scope for v2.0), the observation gap analysis's deferred rows, and decisions
recorded during the July 2026 audit.*

## Deferred to v2.x

- **Debug log parsing.** PHD2 debug logs (`PHD2_DebugLog_*.txt`) carry per-frame
  HFD, exception throws, AutoFind sequences, and mount comm latency, but need
  streaming infrastructure for 18 MB+ files. Unlocks three deferred observers
  (gap analysis, "Debug-log only" table): capture-error spikes, mid-session
  setting changes, and saved-calibration parameter drift.
- **SchemaV2.** First real schema change should rename the stored
  `medianRMSArcsec` attribute to `nightRMSArcsec` (the value is a
  frame-weighted quadrature mean; every user-facing surface already says
  "night RMS"). The `LibraryMigrationPlan` scaffold is registered and waiting;
  add the stage rather than retrofitting plumbing.
- **Localization.** Deliberately deferred (July 2026 audit decision). About 120
  user-facing strings are hardcoded English and no String Catalog exists. Costs
  nothing while English-only; budget a mostly mechanical multi-day retrofit
  before any international push.
- **Wire observation cards' "Learn more" links to the help book.** The help
  topics, `HelpOpener.openByID`, and the card section all exist, but the
  section is deliberately hidden until the help-book anchor IDs are verified
  against the shipped book. Small job; unlocks per-card deep links.
- **100 MB "may take a while" confirmation** on document open (only the 500 MB
  hard refusal shipped; the bulk importer now enforces the same cap).
- **Analysis-fingerprint skip on re-import.** Re-importing an unchanged folder
  re-runs the full parse/analysis on every dedup hit (by design, so threshold
  changes propagate). A fingerprint check would make large re-imports cheap.

## Possibly v2.x, needs its own design pass

- **Pre-flight surface.** "What's the state of my rig before tonight" — distinct
  enough from the library to deserve its own design.
- **Diagnostic wizard.** Guided troubleshooting for users with an active
  problem; a different posture from the library's ambient observations.
- **MCP write channel, app-mediated.** The stdio helper went strictly read-only
  in July 2026 (raw-SQLite writes into the live store were a corruption risk).
  If Claude-driven annotation writing comes back, it must route through the app
  (e.g. the embedded server brokering into the ModelContainer), never through
  direct database access.

## v3 conversations

- **Multi-rig comparison.** "Compare my Edge 11 to my FRA 400." Resist until
  usage patterns surface.
- **Cloud sync.** Local-first remains the posture; cloud pulls in auth,
  conflict resolution, and a backend. The schema is already CloudKit-clean.
- **Real-time monitoring** via PHD2's event server. PHD2 does this well itself.
- **Auto-detection of equipment changes** from external sources (imaging-frame
  EXIF, NINA/SGP logs). Annotations stay user-driven until then.

## Deferred indefinitely

- **Anonymous benchmarking against other users.** Privacy and methodology risks
  outweigh the value; revisit only with a much stronger design.
