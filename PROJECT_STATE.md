# Ephemeris — Project State

*Snapshot for design / strategy reference. Generated from the codebase and not from memory.*

## 1. Summary

Ephemeris is a native macOS app for astrophotographers that reads PHD2 guide logs and turns them into a Mac-native review experience. Users open a `.txt` log produced by [PHD2](https://openphdguiding.org), and the app indexes every guiding and calibration section the file contains, then offers a sidebar of sessions, a time-series chart, an XY calibration plot, statistics rollups (RMS, peak, drift, polar-alignment estimate), an FFT periodogram, multi-session combining, drag-to-zoom and drag-to-exclude, manual-exclusion ranges, and CSV / chart-PNG export. It is a reimplementation of `agalasso/phdlogview` (C++/wxWidgets, GPLv3) in Swift / SwiftUI, with substantially redesigned visuals and analysis code that runs on Apple's Accelerate framework instead of GSL.

## 2. Tech stack

- **macOS deployment target:** 14.0 (Sonoma).
- **Swift version:** 5.0 toolchain (Swift 6 concurrency idioms in places — `Sendable` + `nonisolated` annotations, `MainActor` default isolation via `SWIFT_DEFAULT_ACTOR_ISOLATION`).
- **UI framework:** SwiftUI for everything user-facing. AppKit interop appears in only two places — `WindowSubtitleSetter` (an `NSViewRepresentable` that walks to the `NSWindow` to override the OS-supplied "— Locked" subtitle on read-only documents) and `ExportItems.renderImage` (which uses `ImageRenderer` to produce `NSImage`s). The custom About panel is a SwiftUI `Window` scene with `windowStyle(.hiddenTitleBar)`.
- **Charts:** Apple's Swift Charts (`import Charts`). The main guide chart, calibration plot, scatter cluster inset, frequency-analysis chart, and diagnostic sub-charts all use it.
- **Math:** Apple's Accelerate framework (`vDSP_fft_zripD`, `vDSP_ctozD`, `vDSP_zvabsD`) for the real-FFT periodogram. Everything else is straight Swift.
- **Document handling:** SwiftUI's `DocumentGroup` + `FileDocument`. Logs are opened read-only.
- **Third-party packages:** none. No SPM dependencies, no `Package.swift`. Apple frameworks only.
- **Build system / Xcode:** Xcode 26.4. Project format `objectVersion = 77`. Uses `PBXFileSystemSynchronizedRootGroup` (Xcode-26-style synced groups) so anything dropped into the source folders is auto-included.
- **License:** GPLv3, matching upstream `phdlogview`. See `LICENSE.txt` and `CODE_PROVENANCE.md`.

## 3. Architecture overview

The codebase is layered, but not formally so — there's no MVVM scaffolding or dependency-injection container. The layers are conventions, not enforced boundaries.

**Parsing layer.** `GuideLogParser.parse(_:)` is a pure function that takes a `String` (the raw log file contents) and returns a `GuideLog`. It runs a 5-state machine (SKIP, GUIDING_HDR, GUIDING, CAL_HDR, CALIBRATING) over the lines, dispatching to subordinate helpers — `HeaderParser` for guiding-section header lines, `CalibrationHeaderParser` for the calibration block headers, `InfoCoalescer` for INFO line dedup/replacement rules, and `NonMonotonicFix` for clock-jump repair. Because the parser is called from `GuideLogDocument.init(configuration:)`, parsing currently happens inline on whatever queue SwiftUI's document machinery uses (typically the main actor, sometimes a background queue depending on macOS internals — there's no explicit `Task.detached`).

**Model layer.** Plain `Sendable` value types. `GuideLog` is the top-level container with a list of `SectionRef` (an enum: `.summary`, `.guide(Int)`, `.calibration(Int)`) preserving original section order, plus parallel arrays of `GuideSession` and `Calibration`. Per-frame data lives in `GuideEntry` arrays inside each session. Header metadata lives in `GuideDevice` (mount and optional AO).

**Analysis layer (`Stats/`).** All pure functions / `enum` namespaces, no observable objects. `SessionStatsCalculator.calculate(_:manualExclusionRanges:)` produces a `SessionStats` struct from a `GuideSession`. `LogAggregateStatsCalculator.calculate(_:)` does the frame-count-weighted aggregate. `FrequencyAnalyzer.analyze(...)` produces a `FrequencySpectrum`. `GuideSessionMerger.merge(_:)` synthesises a single virtual session from multiple. `CSVExporter` serialises any of these to CSV strings. None of the analyzers cache results — each call recomputes.

**View layer (`Views/`).** SwiftUI views that read directly from the model, computing analysis on the fly. State of two flavours:
- *Per-window UI state* — `chartSelectedTime`, `manualExclusions`, sidebar `selection`, etc. — held in `@State` on `ContentView` and threaded down by `@Binding`.
- *Persistent chart preferences* — `ChartViewState` is an `@Observable @MainActor final class` that mirrors every preference (units, axis mode, drag mode, Y-scale, every overlay toggle, hover-readout visibility) to `UserDefaults` via per-property `didSet`. One instance is held on `ContentView` and shared across the chart subviews.

**Data flow.** A user drops a `.txt` file → `DocumentGroup` instantiates `GuideLogDocument` → its `init(configuration:)` calls `GuideLogParser.parse(text)` → that returns a `GuideLog` → `ContentView` is bound to that document and routes selections through `SessionDetailView`, `LogSummaryView`, etc. Stats are recomputed every render. There is currently no caching layer; for typical PHD2 logs (a few thousand frames), recomputation is fast enough that nothing blocks the UI.

**Concurrency.** The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` so views are MainActor-isolated by default. Model and stat types are `nonisolated struct` / `nonisolated enum` so they can be passed across actor boundaries cleanly. There are no `Task` blocks, no async pipelines — everything is synchronous.

## 4. Data model

**`GuideLog`** — root container parsed from a single `.txt` file.
Fields: `phdVersion`, `logVersion` (parsed from the top-of-file banner), `sections: [SectionRef]` (chronological), `guideSessions: [GuideSession]`, `calibrations: [Calibration]`. `isEmpty` is true when no sections were recognised.

**`GuideLog.SectionRef`** — enum: `.summary` (sentinel for the aggregate view), `.guide(Int)`, `.calibration(Int)`. The Int indexes into the parallel arrays.

**`GuideSession`** — one PHD2 guiding section. Identifiable via UUID. Fields: `startedAt: Date?` (parsed from `Guiding Begins at …`), `rawHeader: [String]` (verbatim header lines for the inspector), `mount: GuideDevice`, `ao: GuideDevice?`, `pixelScale: Double` (arcsec/px), `declination: Double` (radians), `entries: [GuideEntry]`, `infos: [InfoEntry]`. Computed: `duration` (last entry's time), `frameCount`.

**`GuideDevice`** — config for either the mount or AO. Fields: `kind` (mount/ao), `name`, `xAngle`/`yAngle` (radians), `xRate`/`yRate` (px/sec), `maxRADuration`/`maxDecDuration` (ms), `guidingEnabled`, `minMoveX`/`minMoveY` (px), `xGuideAlgorithm`/`yGuideAlgorithm` (string).

**`GuideEntry`** — a single frame. `Identifiable` by frame number. Fields: `frame`, `time` (seconds since session start), `deviceKind` (mount/ao for that frame), `dx`/`dy` (pixel offset of star from lock), `raRawDistance`/`decRawDistance` (pre-algorithm pixel distance), `raGuideDistance`/`decGuideDistance` (post-algorithm pixel distance), `raDuration`/`decDuration` (signed ms; sign encodes direction — W/S negative, E/N positive), `xStep`/`yStep` (AO step counts; nil for mount), `starMass` (int), `snr` (double), `errorCode` (PHD2 error code, 0/1 mean star-found), `included` (computed from errorCode), `guiding` (whether guiding was enabled at this frame), `info` (optional event text from PHD2).

**`InfoEntry`** — a coalesced PHD2 INFO event tied to a frame. Fields: `frame` (the next frame after the event in the source log), `text`, `repeats` (how many consecutive identical events were folded into this one).

**`InfoKind`** — classified enum derived from `InfoEntry.text` (settling started/complete/failed, dither, mount geometry change, calibration rejected, looping exposures, star lost, frame dropped, parameter change, set lock pos, server event, other). Used for icon/colour selection in the inspector.

**`Calibration`** — one PHD2 calibration section. Identifiable via UUID. Fields: `startedAt: Date?`, `device` (mount/ao), `rawHeader: [String]`, `entries: [CalibrationEntry]`, `details: CalibrationDetails`.

**`CalibrationDetails`** — extracted metadata from the calibration's header lines. Fields: `pixelScale`, `exposureMs`, `calibrationStepMs`, `calibrationDistancePx`, `assumeOrthogonalAxes`, `raGuideSpeedArcsecPerSec`, `decGuideSpeedArcsecPerSec`, `declinationRad`, `hourAngleHours`, `pierSide`, `lockPositionX`/`lockPositionY`, `legCompletions: [Direction: LegCompletion]`. Computed: `orthogonalityErrorDeg` (signed angular distance from 90° between west and north legs).

**`LegCompletion`** — per-direction calibration completion record. `angleDeg`, `ratePxPerSec`, optional `parity` ("Even" / "Odd" / etc.).

**`CalibrationEntry`** — one calibration step. Identifiable via UUID. `direction` (West/East/North/South/Backlash, with Left → west and Up → north for AO logs), `step` (int), `dx`/`dy` (pixels).

**`SessionStats`** — recomputed per-render rollup. `includedFrames`, `excludedFrames`, `rmsRA`/`rmsDec`/`rmsTotal` (pixels), `peakRA`/`peakDec` (pixels, abs deviation from mean), `driftRA`/`driftDec` (px/min), optional `polarAlignErrorArcmin`. There's also a static helper for converting display units.

**`LogAggregateStats`** — same shape but across the whole log. Includes `bestSessionIndex`/`worstSessionIndex` for the summary's pill chips and quality bar.

**`FrequencySpectrum`** — output of the FFT pipeline. `periods: [Double]` (seconds), `magnitudes: [Double]` (normalised so peak == 1), `dominantPeriod: Double?`, plus diagnostic fields `sampleInterval`, `sampleCount` (zero-padded length), `driftCorrected`.

**`ChartViewState`** — view-level (`@Observable @MainActor`). Holds every chart preference and persists each via `UserDefaults`. Counts as part of the data model because its values shape what the chart actually shows.

## 5. Features inventory

### 5a. Currently working features

**Log loading**
- Open via File → Open or drag-and-drop onto Dock / app icon.
- Reads UTF-8 / ASCII; tolerates Windows CRLF (the parser splits on `Character.isNewline`).
- Tolerates malformed rows (silently skipped) and missing fields (defaulted to 0/empty).
- Old PHD2 logs (rates in px/ms instead of px/sec) are auto-corrected via the < 0.05 heuristic.
- Non-monotonic timestamps (NTP jumps mid-session) are repaired using the median positive-delta algorithm; a fake "Timestamp jumped backwards" info marker is inserted at the first jump.

**Summary view**
- Aggregate header strip: guide-session count, calibration count, total integration time, frame counts (included / excluded), pixel scale, weighted RMS RA / Dec / total.
- Best / Worst session capsules in the header — clickable to jump.
- Sortable table of every guiding session with Started, Duration, Frames, RMS RA (red-tinted), RMS Dec (blue-tinted), Total RMS columns.
- Leading "quality" column with green ★ Best / orange ⚠︎ Worst chips on matching rows.
- Total RMS column shows a thin horizontal bar scaled to the worst RMS in the log.

**Sidebar**
- Lists Summary plus every section in chronological order. Per-row icon (crosshair for guide, target for calibration), start time, duration.
- Multi-select with ⌘-click or ⇧-click to combine sessions into one chart.
- Single-select returns to per-section view.

**Per-session guiding view**
- Time-series chart with RA (red, 2pt) and Dec (blue, 2pt) lines, hover/pin selection, drag-to-zoom or drag-to-exclude (modal, switchable).
- Y-scale: Auto, ±0.5″, ±1″, ±2″, ±5″, ±10″. Plot area is clipped so spikes don't bleed into the stats strip.
- Units: Pixels or Arc-sec (toggle). Axes: RA/Dec or dx/dy (toggle).
- Stats strip above the chart: frames, duration, pixel scale, RMS RA, RMS Dec, Total RMS, peak RA, peak Dec.
- Hover readout card fixed to the chart's top-leading corner (toggleable). Shows frame, time, RA, Dec, SNR, plus inclusion state and any nearby info text.
- Pinned selection: clicking a frame anchors the rule (accent-coloured, 2pt) and adds filled circular markers on the RA and Dec data points.
- Overlays menu: RA, Dec, corrections (per-frame pulse bars), star mass sub-chart, SNR sub-chart, events (rule + settling bands), limits (max guide pulse), grid, scatter cluster, hover readout.
- Scatter cluster overlay: square XY scatter inset (top-right of chart), translucent, dashed concentric reference rings every 0.5 unit (matching PHD2's target convention), the cursor-active point highlighted in green and enlarged.
- Settling bands: faint orange when settling failed, neutral grey when succeeded.
- Diagnostic sub-charts: star mass (yellow) and SNR (green), each with its own active rule synced to the main chart's hover.
- Manual exclusion drag: per-session exclusion ranges that filter stats and the scatter overlay; cleared via toolbar button.

**Per-session inspector (right panel)**
- Bordered cards (dark fill + thin separator stroke) for: Session, Statistics, Optics, Mount, AO (when present), Events.
- 12pt trailing margin so the scrollbar doesn't sit flush against card edges.
- Statistics card colour-tints RA and Dec rows (red / blue), shows both pixel and arcsec values for distance metrics, and shows polar-align in arcminutes.
- Mount card lists name, guiding-enabled state, max RA / Dec durations, RA / Dec algorithms, and minimum-move thresholds (axis-tinted dots in front of each).
- Events card icons-by-kind (e.g. checkmark.circle for settling complete, exclamationmark.triangle for star lost). Click any event row to jump the chart's selection rule.

**Calibration view**
- Square XY plot, 1:1 aspect ratio.
- Per-direction line + endpoint label: West/East red, North/South blue, Backlash orange.
- Concentric dashed reference rings at "nice" 1/2/5×10ⁿ radii.
- Header stats strip: device kind, step count, started, RA rate (from West leg), Dec rate (from North leg), orthogonality error (orange if > 5°).

**Frequency analysis**
- Modal sheet (⌘F) showing a log-X-axis FFT periodogram for RA or Dec.
- Drift-correct toggle (default on).
- Vertical rule at the dominant period with annotation, hover readout footer.

**Combined sessions**
- Multi-select sessions in the sidebar to view as a single virtual log.
- Real wall-clock gaps preserved (meridian flips, cloud breaks show as flat sections).
- All single-session features (zoom, exclusion, FFT, export) work on the merged session.

**Export**
- Toolbar Share menu (⌘E):
  - Chart as PNG (rendered via `ImageRenderer` at 2× scale, 1280×600 base).
  - Session stats CSV.
  - Frame data CSV (one row per `GuideEntry`).
  - Log summary CSV (one row per session in the file).
- Delivered through the system share sheet — sandbox-safe, no entitlement required.

**Help**
- In-app Apple Help Book (⌘?) opens Help Viewer with a card-grid landing page and 9 topic pages (getting started, main window, reading the chart, statistics, zoom & exclusions, combining sessions, frequency analysis, calibration, exporting, shortcuts).
- Search index built with `hiutil`.

**About panel**
- Custom SwiftUI window (replacing the system About). Large 160pt app icon, app name, version (from CFBundleShortVersionString + CFBundleVersion), tagline, copyright, Documentation / Support links, acknowledgements footer crediting Andy Galasso.

### 5b. UI surfaces

- **Document window — Summary mode.** Sidebar + aggregate header strip + sortable session table.
- **Document window — Guide-session mode.** Sidebar + stats strip + main chart (with optional scatter inset, hover card overlay) + diagnostic sub-charts + chart-controls bar + inspector.
- **Document window — Calibration mode.** Sidebar + stats strip + XY calibration plot + inspector with calibration-specific cards.
- **Document window — Combined-sessions mode.** Routes through the guide-session UI with a synthesised virtual log, filename appended with `· N sessions combined`.
- **Frequency analysis sheet.** Modal sheet over the document window with the periodogram, axis picker, drift-correct toggle, footer readout.
- **About Ephemeris window.** Standalone hidden-titlebar window with icon, version, links.
- **Help Viewer (Apple Help).** Separate system app launched via the Help menu / ⌘?, displaying the embedded help bundle.

## 6. Analysis subsystems

**Per-session statistics (`Stats/SessionStatsCalculator.swift`).** Two-pass algorithm: filter included frames (and any user manual-exclusion ranges), compute means of `raRawDistance` / `decRawDistance` / `time`, then compute population standard deviation of RA and Dec around their means. Total RMS is the geometric sum. Peak is `max(|value − mean|)`. Drift uses textbook least-squares linear-regression slope of value vs. time, scaled to per-minute. König polar-alignment formula (`3.82 × |drift_dec_arcsec_per_min| / cos δ`) is suppressed when |δ| > 85° because the cosine term explodes. All values stored in pixels; arcsec views multiply by `pixelScale` at display time.

**Aggregate statistics (`Stats/LogAggregateStats.swift`).** Frame-count-weighted RMS — `sqrt(Σ(rms_i² · n_i) / Σn_i)`. Best / worst session indices computed on per-session total RMS. Pixel scale is reported only when all sessions agree (single-system assumption); otherwise it's left at 0.

**Frequency analysis (`Stats/FrequencyAnalyzer.swift`).** Pipeline: filter to included frames (must have ≥ 32) → compute mean dt, build a uniform sample grid of length `N = span/dt + 1` → linear interpolation at the grid points → optional linear-regression detrend, otherwise mean-subtract → Hann window → zero-pad to next power of two → real FFT via `vDSP_fft_zripD` → magnitudes via `vDSP_zvabsD` → drop the DC bin → map bin index `i` to period `N · dt / i` → normalise so the peak is 1. Dominant period is the index of the peak. The Hann window (vs. PHD2's Hamming) and zero-padding (vs. PHD2's no-pad) are deliberate independent choices.

**Calibration geometry (`Model/Calibration.swift` + `Parser/CalibrationHeaderParser.swift`).** Parses per-leg `<Direction> calibration complete. Angle = X deg, Rate = Y px/sec, Parity = Z` lines into `LegCompletion` records. Orthogonality error is the absolute difference between the West-vs-North angle delta and 90°, computed via signed angular distance on the 360° circle. Highlighted orange in the UI when > 5°.

**Multi-session merge (`Stats/GuideSessionMerger.swift`).** Sorts sessions by `startedAt`. When all sessions have wall-clock dates, rebases each session's frame timestamps relative to the earliest start (`offset = startedAt − baseDate`), preserving real-world gaps. Frame numbers are renumbered globally so the inspector remains coherent. When dates are missing, falls back to end-to-end concatenation with a 1-second nominal gap. Pixel scale, declination, and mount config are inherited from the first session.

**INFO coalescing (`Parser/InfoCoalescer.swift`).** Three rules, applied per session: (1) identical text on consecutive frames merges into one entry with `repeats++`; (2) on the same frame, an entry whose `key=` prefix matches the previous entry replaces it (parameter-change deduplication); (3) on the same frame, a `DITHER` event replaces a preceding `SET LOCK POS` (PHD2 emits both — only the dither matters). Behaviour-mirrors `logparser.cpp`.

**Non-monotonic timestamp fix (`Parser/NonMonotonicFix.swift`).** Computes the median of positive deltas across the session (the "typical sample interval"). Walks frames; whenever a delta is ≤ 0, sets the entry's time to `prev + median` and accumulates the corrective offset into all subsequent entries. Inserts a single synthesised `"Timestamp jumped backwards"` info entry at the first jump frame.

## 7. PHD2 log format handling

The parser implements a 5-state machine recognising PHD2's section delimiters (`Guiding Begins at …`, `Frame,Time,mount`, `Guiding Ends`, `Calibration Begins at …`, `Direction,Step,dx,dy,x,y,Dist`, `Calibration complete`). It quote-aware-tokenises the 18-or-19 column guide rows, treats W/S direction tokens as negative durations, overrides `raDuration`/`decDuration` with `xStep`/`yStep` when the latter are non-empty (AO frames), and recognises both mount direction tokens (West/East/North/South/Backlash) and AO synonyms (Left → West, Up → North). Header lines accumulate verbatim and are also pattern-matched into structured fields by `HeaderParser` (mount/AO, axis rates and angles, pixel scale, declination, guide algorithms, minimum-move thresholds). Old-format px/ms rate logs are auto-corrected when a rate < 0.05 (scale by 1000). Malformed rows are silently skipped. Empty fields default to 0. INFO lines are coalesced (see §6). Non-monotonic timestamp jumps are repaired (see §6). No automatic settling-frame exclusion — a frame is excluded only if PHD2 reported `errorCode > 1` or the user has dragged a manual-exclusion range over its time. The Swift parser is a behavioural reimplementation of `agalasso/phdlogview/logparser.cpp` rather than a line-by-line port; see `CODE_PROVENANCE.md` for the full lineage analysis (specific behavioural fingerprints, recommended licensing, attribution language).

## 8. Known limitations and rough edges

- **Combined-session lines connect across gaps.** Multi-session merge produces a single `GuideSession` with one `entries` array, so `LineMark` draws a straight line across the gap between sessions. Functionally correct (the gap is real wall-clock dead time) but visually misleading. A multi-series refactor or session-boundary `RuleMark` would fix this.
- **No cached analysis.** `SessionStats` is recomputed on every render. For typical logs this is fast, but a 30,000-frame combined-session view will recompute on every hover. Has not become a problem, but no caching layer exists.
- **No test for the multi-session UI flow.** `MergerTests` covers the merger function; nothing covers the virtual-log routing in `ContentView.makeVirtualLog`.
- **`assumeOrthogonalAxes` parsed but never displayed** in the calibration inspector card.
- **`hourAngleHours` and `pierSide`** parsed and stored on `CalibrationDetails`; surfaced in the calibration inspector but not used for any analysis.
- **No multi-document comparison.** Each window is one log. Comparing nights requires opening two windows side by side; there's no built-in cross-night view.
- **No keyboard shortcuts for series toggles.** RA / Dec / Corrections / Star mass / SNR / etc. are menu-only.
- **Frame-jump from an event in the inspector** doesn't scroll the chart if the frame is outside the current zoom window. The selection rule is set but invisible.
- **Settling-band detection** is heuristic — looks for adjacent "Settling started" + "Settling complete/failed" pairs. Settling events at session boundaries can be miscounted.
- **About panel "Documentation" link** points at the GitHub README. There is no project website or hosted docs.
- **Frequency analysis Y-axis** is unitless / unlabelled. Magnitudes are arbitrary; only relative comparisons are meaningful.
- **Polar-align estimate is a single-session approximation.** Suppressed near the pole, but no warning when the session is short / drift fit is poor.
- **No export of the FFT / periodogram data.** Frequency analysis is read-only.
- **The legacy `.appiconset` is maintained alongside the `.icon` package.** Apple has no documented "single source" for both Tahoe-and-earlier; we ship both. Means the icon needs updating in two places when the visual changes.
- **Build phase that copies `AppIcon.icon` into the bundle** runs after Xcode's CodeSign step, so the icon directory is not in `CodeResources`. macOS accepts this for non-executable resources, but App Store distribution may require a re-sign workaround.
- **`CFBundleIconFile` and `CFBundleIconName`** both set to `AppIcon` by `actool`; runtime preference is intentional but not documented in-app.
- **No high-DPI testing of help book CSS.** Verified visually in Safari but not in Help Viewer at scaled-up text-size accessibility settings.

## 9. Not-yet-implemented features the human has discussed

- **Interpretive / plain-language verdict layer.** Greenfield. No scaffolding. `SessionStats` produces numbers but nothing classifies "this is good / mediocre / bad" or annotates *why* (e.g. "0.8″ RMS with 0.3″/min Dec drift suggests polar misalignment, not seeing"). Would be a new module that takes `SessionStats` + `GuideSession` + `CalibrationDetails` and emits structured findings. The chip-style design language already in `LogSummaryView` (Best / Worst pills) is a ready visual idiom for surfacing verdicts.
- **Pattern detection (periodic error, polar misalignment, backlash).** Partial scaffolding. `FrequencyAnalyzer` already finds a dominant period; there's no logic that *interprets* it ("this 480s spike on RA looks like worm-gear PE for an SkyWatcher EQ6"). Polar-align estimate exists. Backlash is detectable in calibration data (`Backlash` direction entries) but not analysed. Cross-axis correlation is greenfield.
- **Cross-session trend analysis.** Greenfield. `LogAggregateStats` aggregates but doesn't trend. There's no concept of comparing across multiple log files. Would require either a multi-document UI or a dedicated "library" view that ingests a folder of logs.
- **MCP server for conversational analysis.** Fully greenfield. The Swift app has no IPC / network exposure. The data structures (especially `GuideLog`, `SessionStats`, `LogAggregateStats`) are `Sendable` and serialisable, so they could be re-shaped into a CLI / MCP tool with modest effort. The CSV exporter already proves the data model serialises cleanly.
- **PHD2 debug log parsing.** Greenfield. Ephemeris reads only the guide log (`PHD2_GuideLog_*.txt`), not the PHD2 debug log (`PHD2_DebugLog_*.txt`). Correlating the two would require a second parser plus a UI surface for the correlation. The `infos`-on-frame model is the obvious place to thread debug events into the existing chart.

## 10. Build, run, test

**Build:**
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Ephemeris.xcodeproj -scheme Ephemeris build
```
The scheme is `Ephemeris`. Output ends up under `~/Library/Developer/Xcode/DerivedData/Ephemeris-*/Build/Products/Debug/Ephemeris.app`.

**Run:** Open the `.app` from DerivedData, or `open` it from the CLI.

**Tests:** `xcodebuild ... test` runs the `EphemerisTests` and `EphemerisUITests` targets. As of writing, ~56 unit tests cover: parser (CRLF, sections, calibration, info kinds, coalescing rules), session stats (RMS, drift, peak, polar-align), aggregate stats, frequency analyzer (sine recovery, drift removal, edge cases), CSV exporter, calibration header parser, and the multi-session merger. UI tests are minimal — a launch test and an empty `testExample`.

**Sample log:** `EphemerisTests/Fixtures/sample_short.txt` — a small bundled log used by the parser and stats tests. No real-world logs are committed (deliberately — they'd be large and contain timestamps that look like personal data).

**Developer-only debug features:** None. There's no debug menu, no profiling logging, no internal inspector. Print statements are absent.

## 11. File map (compact)

```
Parser/        — turns text into model
  GuideLogParser.swift          Top-level state machine + entry-row tokenizer
  HeaderParser.swift             Guiding-section header line parser (mount/AO/algos)
  CalibrationHeaderParser.swift  Per-direction completion lines, lock pos, pier side, etc.
  InfoCoalescer.swift            Three-rule INFO event dedup / replacement
  NonMonotonicFix.swift          Median-delta clock-jump repair

Model/         — pure data structures
  GuideLog.swift           Top-level container + GuideDevice
  GuideSession.swift       GuideSession, GuideEntry, InfoEntry
  Calibration.swift        Calibration, CalibrationDetails, LegCompletion, CalibrationEntry

Stats/         — analysis (no caching, all enums of static funcs)
  SessionStats.swift              Stats struct + display-unit conversion helper
  SessionStatsCalculator.swift    Per-session RMS / peak / drift / polar-align
  LogAggregateStats.swift         Frame-count-weighted aggregate, best/worst
  FrequencyAnalyzer.swift         Hann + Accelerate vDSP real-FFT periodogram
  GuideSessionMerger.swift        Multi-session stitching with wall-clock rebasing
  CSVExporter.swift               Three CSV serializers (session / frames / aggregate)

Document/      — file I/O
  GuideLogDocument.swift   FileDocument; opens read-only via DocumentGroup

Views/         — SwiftUI UI
  ContentView.swift               Top-level NavigationSplitView, selection routing
  EphemerisApp.swift              @main scene + custom About window scene
  AboutView.swift                 Custom About panel (icon, version, links)
  ChartViewState.swift            @Observable persisted chart preferences
  SessionListView.swift           Sidebar list of sections
  LogSummaryView.swift            Aggregate header + sortable session table with quality bar
  SessionDetailView.swift         Routes to guide / calibration / virtual log; chart-controls bar
  GuideGraphView.swift            Main time-series chart, hover/pin, settling bands, drag
  ScatterInsetView.swift          Translucent overlay scatter cluster with reference rings
  DiagnosticGraphView.swift       Star mass / SNR sub-charts
  CalibrationGraphView.swift      Square XY calibration plot with reference rings
  FrequencyAnalysisView.swift     FFT periodogram modal sheet
  SessionInspectorView.swift      Bordered-card inspector for guide and calibration
  ExportItems.swift               Transferable wrappers for ShareLink (CSV + PNG)
  WindowSubtitleSetter.swift      AppKit hop to override "— Locked" subtitle

Top-level resources:
  Assets.xcassets/AppIcon.appiconset/    Legacy PNGs for macOS 14/15 (.icns target)
  AppIcon.icon/                          Icon Composer Liquid Glass package for macOS 26
  Credits.html                           Legacy About-panel credits (now unused — custom AboutView)
  Info.plist                             Custom partial — help book + copyright keys
  Ephemeris Help.help/                   Apple Help Book bundle (HTML + helpindex)

Tests:
  EphemerisTests/      Unit tests (parser, stats, FFT, merger, CSV)
  EphemerisUITests/    UI smoke tests (launch only)
  Fixtures/sample_short.txt    Small log fixture

Project root:
  README.md            Public-facing intro + attribution + license
  LICENSE.txt          Canonical GPL-3.0
  CODE_PROVENANCE.md   Formal lineage analysis vs phdlogview
  PROJECT_STATE.md     This document
```
