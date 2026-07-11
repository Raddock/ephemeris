# Ephemeris 2.0 — Design Document

*Multi-night library, recommender engine, annotations, and help system*

> **Status (July 2026): shipped.** All twelve build phases (§10) are implemented
> on the `v2` branch and the open questions (§12) were resolved during
> implementation. This document is preserved as the design the build followed;
> it is no longer a plan. Current app state: `PROJECT_STATE.md`. Remaining
> future work: `ROADMAP.md` (which absorbs §11's deferred items).

---

## 0. Purpose of this document

This document specifies the architectural and feature direction for Ephemeris 2.0 — the transition from a single-night PHD2 guide log viewer to a multi-night analytical library with a recommender engine, persistent annotations, and a first-class help layer.

It is intended as the master design spec from which sprint-sized implementation prompts can be derived for handoff to Claude Code. It is not implementation-detailed in the sense of API signatures or SwiftUI view hierarchies; those are derived during implementation. It is detailed at the level of *posture, principles, architecture, data model, and build sequence*.

The current app state is captured in `PROJECT_STATE.md`. This document supersedes nothing in that file — it adds. The 1.x app remains the foundation; 2.0 builds on it.

---

## 1. Vision and posture

Ephemeris 2.0 is an **honest analytical layer over PHD2 guide logs** — one that knows what it can claim, defers where it can't, and helps the user reach the answers software alone can't compute.

The vision can be stated in a single paragraph:

> *Ephemeris analyzes what PHD2 produces, finds patterns across nights that no single session can show, surfaces the data the user needs to diagnose their own setup, and points back to PHD2's own tools when those tools are the right answer. Where guide logs cannot answer the user's question — differential flexure, mechanical state, environmental conditions — the app says so plainly and provides educational context to help the user reason about it.*

This posture has three implications worth being explicit about:

**The app does not pretend to know things it cannot know.** Sub-frame quality, optical-train physical state, environmental conditions, equipment changes, the user's operational habits — none of these are derivable from guide logs alone. The app must be designed to surface these gaps rather than paper over them with confident-sounding claims.

**The recommender's authority comes from restraint, not coverage.** A recommendation that says *"based on the evidence in your logs, X is one possible explanation; running PHD2's Guiding Assistant will give you a definitive measurement"* is more credible than *"set aggressiveness to 65%."* The differential voice is the signature.

**The help system is not peripheral.** Because the recommender deliberately under-claims, the help system fills the gap. A user reading *"this could be flexure"* needs to know what flexure is, how to detect it, what to do about it. The help layer is what makes the recommender's restraint feel intentional rather than evasive.

---

## 2. The twelve throughlines

These are design principles, in priority order. Every feature decision in 2.0 should be checkable against this list. They emerged from the design conversation that produced this spec and are documented here as an appendix to the architecture itself.

**1. Don't overclaim causation.** The recommender presents observations, possible contributors (always plural), and suggested responses (always coaching, never imperative). The differential voice — *what was measured, what it could mean, what would help disambiguate* — is the default register.

**2. Anchor everything to imaging scale.** The user's imaging pixel scale is the lens through which guide RMS is interpreted. Without it, recommendations are abstract. With it, the same RMS yields different verdicts on different rigs. Imaging scale is the foundational input to nearly every observation the engine produces.

**3. Know what the user did.** Equipment changes, calibrations, polar realignments, software updates, environmental events — none of these are visible in guide logs. The annotations layer is how the engine learns what the user did, and how recovery patterns, trend breaks, and other temporal discontinuities get correctly attributed.

**4. Reference PHD2 tools by name — and use PHD2's measured numbers, not parallel heuristics.** PHD2 ships fourteen named tools (Calibration Assistant, Guiding Assistant, Drift Alignment, Static Polar Alignment, Polar Drift Alignment, Manual Guide, Star Cross, Calibration Review & Modification, Auto-Select Stars, Meridian Flip Calibration, Comet Tracking, Lock Positions, PHD2 Server, Diagnostic Image Logging). The recommender's suggested responses resolve to these tools by name with canonical capitalization rather than producing competing parameter advice. Equally: when PHD2 has *measured* a value (Guiding Assistant's recommended min-move, recommended exposure, backlash, polar-alignment error; the Calibration Assistant's orthogonality/rates), the recommender surfaces PHD2's number verbatim — never a parallel computation. Ephemeris is a layer over PHD2, not a competitor to it. When advice exists outside PHD2's documentation (e.g., harmonic-mount tuning), the recommender labels it as community consensus rather than canon.

**5. Separate optical-train from tracking observations.** *"What the mount is doing"* and *"what the guide camera is seeing"* are different categories with different fixes. The recommender must surface them as distinct observation classes so users don't reach for the aggressiveness slider when their optics are out of focus.

**6. Coaching voice over diagnostic voice.** Most users have healthy rigs and normal operator variance. Default register is coaching — *"your PA estimates have been inconsistent across nights; tightening the alignment routine would reduce variance"* — not diagnostic. Diagnostic voice is reserved for the small number of cases where evidence is overwhelming.

**7. Cross-night vs. single-night taxonomy.** Different observations live in different surfaces. Single-night observations belong in the document window. Cross-night observations belong in the library window. They have different visual treatments and different rhetorical force; mixing them confuses both.

**8. Pointing context normalizes confounds.** Galactic latitude, hour angle, pier side, target identity — all derivable from guide log headers. Star pool size, drift behavior, and RMS distributions vary with these even on a healthy rig. The engine must condition its observations on pointing where relevant.

**9. The imaging frame is ground truth, not the guide log.** Differential flexure can produce great guide RMS and trailed subs simultaneously. The engine cannot detect this from logs alone. The opt-in sub-quality feedback loop is how the engine knows when its confident verdicts are betraying the user.

**10. Equipment state is mutable and silent.** Camera rotation, filter changes, focuser swaps, cable rerouting — these silently invalidate calibration and balance. The engine should detect signal discontinuities (calibration angle shifts, baseline rotations, sudden RMS changes) as candidates for state change events and either prompt the user to annotate or confirm against existing annotations.

**11. Mechanical-first triage.** PHD2 documentation states 99% of "guiding problems" are equipment or operational, not algorithmic. The recommender should reflect this in its priority ordering: sub-quality and optical-train observations first, equipment hygiene second, PHD2-tool freshness third, parameter patterns last. The ordering is itself a design statement.

**12. Multiple moments of user need.** Pre-flight (about to set up), post-mortem (just finished tonight), trend (this week), diagnostic (something is broken), help-prep (need to ask the forum). Different surfaces serve different moments. v2.0 ships post-mortem (existing document window) and trend (new library window). Pre-flight, diagnostic flow, and help-prep are deferred to v2.x.

---

## 3. Architecture overview

### 3.0 Platform requirements

v2.0 raises the deployment floor from macOS 14 (Sonoma) to **macOS 15 (Sequoia)**. The reason is SwiftData: macOS 14's SwiftData has documented rough edges that the v2.0 persistence layer would have to work around at every layer — inverse-relationship `@Observable` notifications drop, `ModelActor` + `@Query` cross-context refresh is unreliable, `#Predicate` can't traverse many to-many relationships, array attributes don't preserve order. Sequoia is where SwiftData stabilized. The Sonoma-but-not-Sequoia user share in 2026 is small enough that the engineering tax of supporting both isn't worth the audience size.

Toolchain: Xcode 26, Swift 6 isolation idioms (`Sendable` + `nonisolated`, `MainActor` default isolation), SwiftUI as the primary UI framework with AppKit interop only at the boundaries.

### 3.1 Layered architecture

Ephemeris 2.0 introduces three new architectural layers on top of the existing 1.x parser/analysis/document-window stack.

```
┌─────────────────────────────────────────────────────────┐
│  Surfaces                                               │
│  ┌────────────────────┐  ┌────────────────────┐         │
│  │  Document window   │  │  Library window    │         │
│  │  (per-log, exists) │  │  (per-rig, new)    │         │
│  └────────────────────┘  └────────────────────┘         │
│  ┌────────────────────────────────────────────┐         │
│  │  Help system (cross-cutting, new)          │         │
│  └────────────────────────────────────────────┘         │
│  ┌────────────────────────────────────────────┐         │
│  │  MCP server (agentic surface, new)         │         │
│  │  - Local stdio MCP server                  │         │
│  │  - Read-mostly tools over library store    │         │
│  │  - Claude Desktop / Claude Code clients    │         │
│  └────────────────────────────────────────────┘         │
├─────────────────────────────────────────────────────────┤
│  Recommender engine (new)                               │
│  - Observation records                                  │
│  - Categories: sub-quality, optical-train, hygiene,     │
│    equipment, pattern, suggestion                       │
│  - Voice rules and severity tiers                       │
├─────────────────────────────────────────────────────────┤
│  Persistence layer (new)                                │
│  - SwiftData store (SQLite under the hood)              │
│  - Schema: RigProfile, NightRecord, Observation,        │
│    Annotation, TargetCluster, GAResult                  │
│  - VersionedSchema + SchemaMigrationPlan for migrations │
│  - Local-first, no cloud sync                           │
├─────────────────────────────────────────────────────────┤
│  Distribution (new)                                     │
│  - Sparkle 2.x auto-update framework                    │
│  - EdDSA-signed appcast hosted on GitHub Releases       │
│  - Check-for-updates menu + automatic background checks │
├─────────────────────────────────────────────────────────┤
│  Existing 1.x stack (unchanged)                         │
│  - GuideLogParser, HeaderParser, CalibrationHeaderParser│
│  - GuideLog, GuideSession, Calibration model types      │
│  - Stats: SessionStatsCalculator, FrequencyAnalyzer,    │
│    LogAggregateStats, GuideSessionMerger, CSVExporter   │
│  - Document window views: ContentView, GuideGraphView,  │
│    CalibrationGraphView, SessionInspectorView, etc.     │
└─────────────────────────────────────────────────────────┘
```

**Key architectural decisions:**

- The document window stays exactly as it is in 1.x, with additive enhancements (annotation indicators, observation chips, help links). It does not become a multi-night view.
- The library is a separate macOS scene — a **`WindowGroup(id: "library")`** opened via `@Environment(\.openWindow)`, not a tab inside `DocumentGroup`. `WindowGroup` (rather than `Window`) is the right primitive because the library is rig-scoped: it needs to carry a data binding (the active `RigProfile`), host `.commands` for menu integration, and compose cleanly with `modelContainer(for:)`. `Window` does none of those reliably. The single-library-at-a-time UX is enforced via `.defaultSize` + the existing window of the same ID being brought to front by `openWindow(id:)`.
- PHD2 `.txt` documents opened via `DocumentGroup` are **`FileDocument`s, not SwiftData-backed models.** They emit side-effect writes into the application-level library store via a `ModelActor` during ingest. The DocumentGroup container and the library WindowGroup container are distinct stores (one transient per-document, one persistent at `~/Library/Application Support/Ephemeris/Library.store`) to avoid the documented SwiftData failure mode of two scenes opening the same SQLite URL.
- The persistence layer is **SwiftData** (Apple's Swift-native framework, backed by SQLite). All user data lives locally at `~/Library/Application Support/Ephemeris/`; no cloud sync, no remote sync. SwiftData was chosen over raw SQLite or GRDB because it honors the Apple-frameworks-only posture inherited from 1.x, provides `@Model`/`@Query` integration with SwiftUI, and addresses schema migration via `VersionedSchema` + `SchemaMigrationPlan` rather than a hand-rolled migrator.
- The recommender engine is a single module that consumes parsed log data + rig profile + annotations and produces typed `Observation` records. Both the document window and the library window consume these records and render them as appropriate to their context.
- The help system is cross-cutting — accessible from anywhere via Apple Help (existing) but with deep links into specific topics from observation cards.
- **Distribution uses Sparkle 2.x** for auto-updates. Sparkle is the one third-party dependency v2.0 adopts (introduced via SPM) — the Apple-frameworks-only posture from 1.x is relaxed here because Apple ships no equivalent for non-MAS apps, and shipping updates without it would require users to manually download every release. The appcast is hosted on GitHub Releases alongside the signed `.dmg` / `.zip` artifacts, signed with an EdDSA key whose public half is embedded in the app bundle. v2.0's only outbound network traffic is the periodic appcast check.

### 3.2 Apple frameworks adopted in v2.0

v2.0 extends the 1.x framework footprint (SwiftUI, Swift Charts, Accelerate, Apple Help) with the following. Each is called out so implementation phases can reference them by name:

- **SwiftData** (`@Model`, `@Query`, `ModelActor`, `VersionedSchema`, `SchemaMigrationPlan`) — persistence layer. See §10 Phase 3.
- **Observation** (`@Observable`) — already in 1.x for `ChartViewState`; extended in v2.0 to a thin `ObservationStore` wrapping `[Observation]` queries so SwiftUI re-renders at property granularity, not object granularity.
- **TipKit** — for the library-discovery tip (third-night moment) and the rig-profile first-run prompt. Replaces the spec's earlier auto-reveal behavior, which violated macOS HIG.
- **CoreSpotlight + App Intents `IndexedEntity`** — index `NightRecord`, `RigProfile`, and `Annotation` so they're findable from system Spotlight. v2.0's closest analogue to "sync" without a backend.
- **App Intents / App Shortcuts** — three actions: *Open most recent log for [rig]*, *Show this week's trends for [rig]*, *Add annotation to last night*. The last is the load-bearing one (users routinely want to record events via hotkey or Shortcuts).
- **CryptoKit** (`SHA256`) — content-hash dedup on `NightRecord.sourceContentHash`. Replaces any CommonCrypto temptation.
- **`AttributedString(markdown:)`** — for in-app rendering of observation card summary / evidence text and any help-system content shown inline (the help-bundle HTML remains for Help Viewer).
- **`ContentUnavailableView`** — empty-state surfaces in the library (first-run, valid-but-empty time ranges). Replaces the design doc's earlier "disable the tab" behavior.
- **`inspector(isPresented:)` modifier** — replaces the 1.x custom inspector implementation; system-managed width, ⇧⌘0 command, free Liquid Glass treatment on macOS 26.
- **NSHelpManager** (`openHelpAnchor(_:inBook:)`) — preferred over raw `help:anchor=` URLs for deep links from observation cards. More reliable about relaunch / same-anchor navigation.
- **Sparkle 2.x** — auto-update framework (the one third-party dependency). See §10 Phase 0.

**Researched and rejected for v2.0** (noted so implementers don't reach for them): Foundation Models / on-device LLM (macOS 26+ only; non-deterministic narrative generation conflicts with throughline #1 "don't overclaim"), Quick Look Thumbnailing extension (Sequoia killed legacy `.qlgenerator`, needs a new app-extension target — deferred to v2.1), UserNotifications (the throughlines warn against unsolicited "your calibration is stale" pings), CoreML/CreateML (learned models can't explain why they flagged something — defer indefinitely), WeatherKit / MapKit (off-mission).

---

## 4. Data model additions

The existing 1.x model types (`GuideLog`, `GuideSession`, `GuideEntry`, `Calibration`, `CalibrationDetails`, `SessionStats`, etc.) are unchanged. The new types added in 2.0:

**Schema rules (applied uniformly across every `@Model` type below):**

Even though v2.0 ships local-only, the schema is designed to be CloudKit-clean so that a future v3 sync addition is a configuration change, not a data-rewriting migration. The cost of these rules in a local-only setting is essentially zero; the cost of *not* adopting them up front and migrating later is real.

1. **No `@Attribute(.unique)` constraints** — CloudKit doesn't support unique indexes. Uniqueness on `sourceContentHash` and similar fields is enforced in the ingest `ModelActor` (check-then-insert inside a transaction), not by SwiftData.
2. **Every `@Relationship` is declared optional** (`var rigProfile: RigProfile?`) — CloudKit requires nilability on every relationship. Application code can still enforce non-nil at the boundary.
3. **Every attribute has a default value at declaration** (`var nightDate: Date = .now`, `var sessionsCount: Int = 0`) — CloudKit can't materialize records without defaults.
4. **`[String]` and similar ordered arrays are stored as Codable-encoded `Data`** when order matters (e.g., `nameHistory`) — SwiftData doesn't preserve array ordering on fetch in 14.x and 15.x.

The shapes below are written in design-doc shorthand; SwiftData declarations apply the rules above.

### `RigProfile`
Per-PHD2-profile equipment metadata. Stable identifier across rename and reconfiguration.

```
RigProfile
├── id: UUID                           // stable across renames
├── currentName: String                // matches PHD2 profile name
├── nameHistory: [String]              // for re-association
├── imagingFocalLength: Double          // mm
├── imagingPixelSize: Double            // μm
├── imagingBinning: Int                 // 1, 2, 3
├── imagingPixelScale: Double           // computed, cached
├── reducerFactor: Double?              // 1.0 = none
├── guideConfiguration: enum            // .oag, .guideScope, .sameOptics
├── guideCameraPixelSize: Double        // μm
├── mountModel: String?                 // free text or curated list
├── mountClass: MountClass              // see below; drives advice
├── hasHighPrecisionEncoders: Bool      // PHD2 wizard checkbox; surfaced from profile XML
├── typicalSubExposure: Int?            // seconds
├── notes: String?                      // free-text user notes
├── createdAt: Date
└── modifiedAt: Date
```

### `MountClass`
Drives algorithm/exposure/min-move advice. PHD2's manual recognizes only three classes by name + AO; the fourth is community-consensus territory and must be labeled as such in any observation that references it.

```
MountClass (enum)
- standardGearMount       // worm-and-gear / belt — PHD2's default class
- encoderBasedPremium     // 10Micron, AP encoder, Planewave, ASA
                          // PHD2's "high-precision encoders" checkbox lands here
                          // Manual explicitly recommends LowPass2 + Variable Exposure Delays
- harmonicStrainWave      // ZWO AM5, iOptron HEM/HAE, Pegasus NYX, WarpAstron
                          // PHD2 manual is SILENT on this class
                          // Recommender advice here is community consensus, not canon
- adaptiveOptics          // SX AO, ONAG, Innovations Foresight
                          // Algorithm dropdown collapses to AO-only choices
```

### `NightRecord`
Per-night analytical artifact. One record per `.txt` log file ingested.

```
NightRecord
├── id: UUID
├── rigProfileId: UUID                 // FK
├── sourceFilePath: String             // original log file
├── sourceContentHash: String          // SHA-256 for dedup
├── nightDate: Date                    // local date of session start
├── sessionsCount: Int
├── totalIntegrationMinutes: Double
├── medianRMSArcsec: Double
├── bestSessionRMSArcsec: Double
├── worstSessionRMSArcsec: Double
├── sessionStats: [PersistedSessionStats]   // compact serialization
├── calibrationData: PersistedCalibration?  // most recent cal in this log
├── pointingTargetClusters: [UUID]          // FK to TargetCluster
├── annotations: [Annotation]               // events for this night
├── ingestedAt: Date
└── lastAnalyzedAt: Date
```

### `Observation`
A typed analytical finding with evidence, severity, and suggested response. Both single-night and cross-night observations use this same schema.

```
Observation
├── id: UUID
├── scope: enum                        // .singleNight, .crossNight
├── rigProfileId: UUID
├── nightRecordIds: [UUID]             // [single] or [many]
├── category: enum                     // see below
├── severity: enum                     // see below
├── title: String                      // short, scannable
├── summary: String                    // 1-2 sentences
├── evidence: [EvidenceItem]           // bullet-list quality
├── candidateContributors: [String]    // always plural
├── suggestedResponse: String          // coaching voice
├── relatedHelpTopicIds: [String]      // deep links
├── relatedPHD2Tools: [PHD2Tool]       // CA, GA, DriftAlign, etc.
├── confidence: enum                   // .high, .medium, .low
├── sourceAuthority: enum               // see below — distinguishes canon vs heuristic
├── generatedAt: Date
└── dismissedAt: Date?                 // user can dismiss
```

**`Observation.sourceAuthority`** is the integrity guard for throughline #4. Every observation declares where its advice comes from. The UI surfaces this — `.phd2Manual` observations are rendered with a "from PHD2 documentation" badge; `.communityConsensus` observations are rendered with a "community consensus" badge and a softer suggested-response voice.

```
SourceAuthority (enum)
- phd2Manual           // Directly cited from PHD2's manual / Best Practices
                       // (e.g. "PHD2 recommends LowPass2 for encoder mounts")
- phd2Measurement      // PHD2 itself measured this — verbatim from GA / Cal Assistant log INFO
                       // (e.g. "Guiding Assistant suggested Dec min-move = 0.18 px")
- phd2BehaviorDocumented // PHD2 source/log behavior PHD2 documents as alerts
                       // (the 4 calibration sanity alerts, max-duration limits, star-lost codes)
- communityConsensus   // Not in PHD2 docs but widely accepted
                       // (harmonic-mount tuning, OAG vs guide-scope wisdom)
- ephemerisHeuristic   // Computed from the corpus by Ephemeris itself
                       // (rig-relative RMS tiers, atmospheric conditions proxy)
```

**Observation categories** (in priority order from throughline 11):
1. `subQuality` — sub-imaging discrepancy when sub-quality feedback is available
2. `opticalTrain` — multi-star count, HFD, star mass, SNR floor patterns
3. `equipment` — calibration angle drift, baseline rotation, suspected state changes
4. `phd2Hygiene` — calibration freshness, GA recency, profile mismatch
5. `pattern` — drift, polarity, oscillation patterns across the corpus
6. `suggestion` — imaging-side decisions like binning, integration time

**Severity tiers:**
- `alert` — strong evidence of a genuine problem (rare)
- `pattern` — observed, named pattern requiring user judgment
- `equipment` — optical-train or mechanical category
- `hygiene` — PHD2 tool freshness or configuration
- `suggestion` — imaging-side decisions
- `coaching` — process improvements within normal operation

### `Annotation`
User-recorded event tied to a night. Captures what the engine cannot observe.

```
Annotation
├── id: UUID
├── rigProfileId: UUID
├── nightRecordId: UUID
├── eventDate: Date
├── categories: Set<AnnotationCategory>
├── label: String                       // short, displayed on chart
├── detail: String                      // longer free-text
├── isRigMutating: Bool                 // triggers profile update prompt
├── createdAt: Date
└── modifiedAt: Date
```

**Annotation categories** (the recommender uses these to suppress or contextualize observations — e.g., a "new calibration" annotation silences `calibrationAngleShift` for the boundary night):

- `equipment` — replaced OAG, swapped guide camera, new focuser, rebalanced, cable rerouted, dew heater toggled
- `calibration` — new PHD2 calibration (Calibration Assistant), new mount sky model (e.g. 10Micron 100-point model), drift-aligned PA, ran Guiding Assistant, ran Static Polar Alignment, ran Meridian Flip Calibration
- `environment` — temperature drop, wind, dew, transparency notes, atmospheric instability ("could see scintillation by eye"), high cirrus, fire smoke
- `software` — PHD2 version change, ASCOM driver update, profile change, **Variable Exposure Delays enabled/disabled**, aggressiveness change, min-move change, algorithm change (Hysteresis → LowPass2 etc.), Multi-star toggled
- `freeText` — anything else

### `TargetCluster`
Sessions clustered by pointing similarity (within ~0.5° tolerance). Enables target-aware analysis.

```
TargetCluster
├── id: UUID
├── rigProfileId: UUID
├── centerRA: Double                    // hours
├── centerDec: Double                   // degrees
├── radius: Double                      // degrees, tolerance
├── catalogMatch: String?               // resolved name (M51, NGC 7000, etc.)
├── nightRecordIds: [UUID]
├── sessionCount: Int
├── totalIntegrationMinutes: Double
└── medianRMSArcsec: Double
```

### `PHD2Tool`
Reference to a PHD2 tool by name + canonical documentation URL. Used by observations to resolve their suggested responses. **Capitalization matches PHD2's manual exactly** — these are proper nouns in the recommender's voice.

```
PHD2Tool (enum or struct, each with displayName + docAnchor)
- calibrationAssistant            // "Calibration Assistant"               Tools.htm#Calibration_Assistant
- guidingAssistant                // "Guiding Assistant"                   Tools.htm#Guiding_Assistant
- calibrationReviewModification   // "Calibration Review and Modification" Tools.htm#Review_Calibration_Data
- driftAlignment                  // "Drift Alignment"                     Tools.htm#Drift_Align
- staticPolarAlignment            // "Static Polar Alignment"              Tools.htm#Static_Polar_Alignment
- polarDriftAlignment             // "Polar Drift Alignment"               Tools.htm#Polar_Drift_Align
- autoSelectStars                 // "Auto-Select Stars"                   Tools.htm#Auto_Find_Star
- manualGuide                     // "Manual Guide"                        Tools.htm#Manual_Guide
- starCross                       // "Star Cross Tool"                     Tools.htm#Star_Cross_Test
- meridianFlipCalibration         // "Meridian Flip Calibration Tool"      Tools.htm#Meridian_Flip
- cometTracking                   // "Comet Tracking"                      Tools.htm#Comet_Tracking
- lockPositions                   // "Lock Positions"                      Tools.htm#Lock_Position
- phd2Server                      // "PHD2 Server"                         Advanced_settings.htm#Server_Tab
- diagnosticImageLogging          // "Diagnostic Image Logging"            Advanced_settings.htm#Global_Tab
```

### `PHD2Algorithm`
Reference to a PHD2 guide algorithm + mount-class suitability + PHD2's own recommendation (or deprecation).

```
PHD2Algorithm (enum or struct)
- hysteresis        // RA default on standard mounts
- resistSwitch      // Dec default; recommended for any axis with backlash
- lowpass           // DEPRECATED per PHD2 manual; treat historical logs but never recommend
- lowpass2          // PHD2 manual explicit pick for encoder mounts
- zFilter           // PHD2's manual: "not generally recommended"
- predictivePEC     // RA-only; gear/worm with residual PE; community pick for harmonic
- identity          // AO devices only; pass-through
```

### Mount-class × algorithm recommendation matrix

Lookup table the recommender consults for `algorithmMismatchObserver`. When the active session's configuration deviates from the rig's class row, the observation cites the specific delta and the matrix's `sourceAuthority`.

| MountClass             | RA algorithm     | Dec algorithm    | Exposure  | Min-move    | Backlash comp     | VarExpDelays | Source authority    |
|------------------------|------------------|------------------|-----------|-------------|-------------------|--------------|---------------------|
| `.standardGearMount`   | Hysteresis (def) | ResistSwitch     | 1–3 s     | per GA      | per GA if <3 s    | off          | `phd2Manual`        |
| `.encoderBasedPremium` | **LowPass2**     | **LowPass2**     | **4+ s**  | high        | off               | **on**       | `phd2Manual`        |
| `.harmonicStrainWave`  | PPEC / Hysteresis| ResistSwitch     | 0.5–1 s   | low         | off               | off          | `communityConsensus`|
| `.adaptiveOptics`      | Hysteresis (high)| Hysteresis (high)| AO-specific| AO-specific| n/a               | n/a          | `phd2Manual`        |

The `.encoderBasedPremium` row is verbatim from the PHD2 manual (`Guide_algorithms.htm#LowPass2`, `Advanced_settings.htm#Camera_Tab`). The `.harmonicStrainWave` row is community consensus only — the PHD2 manual is silent on strain-wave drives, so every observation citing this row must label its authority as such.

### `GAResult`
Parsed Guiding Assistant result from log INFO entries. The recommender surfaces these **verbatim** — observations cite PHD2's measured numbers, not parallel computations (throughline #4 secondary clause).

```
GAResult
├── nightRecordId: UUID
├── runAt: Date
├── durationSec: Int                    // how long GA was running
├── recommendedRAMinMove: Double?       // px — PHD2 INFO: "Suggested RA min-move"
├── recommendedDecMinMove: Double?      // px — PHD2 INFO: "Suggested Dec min-move"
├── recommendedExposureSec: Double?     // seconds
├── polarAlignErrorArcmin: Double?      // PHD2 INFO: "Polar alignment error"
├── decBacklashMs: Double?              // milliseconds — PHD2 INFO: "Dec backlash"
├── decBacklashAssessment: enum         // .none (<100ms), .compensate (100-3000ms), .uniDirectional (>3000ms)
├── raPeakToPeakArcsec: Double?
├── raMaxRateOfChangeArcsecPerSec: Double?
├── highFreqStarMotionArcsecRMS: Double? // PHD2's own "seeing" measurement
├── recommendedBacklashCompensationMs: Int?
└── rawText: String                     // verbatim INFO block for surfacing
```

The `highFreqStarMotionArcsecRMS` value is PHD2's own seeing estimate and is the **only** seeing measurement the recommender should cite as authoritative. Star mass CV (corpus-derived) is `ephemerisHeuristic`-authority; GA's HF star motion is `phd2Measurement`-authority. The recommender uses both, but with different rhetorical force.

---

## 5. Surfaces and scenes

### 5.1 Document window (existing, lightly enhanced)

The single-log document window from 1.x. Continues to be the primary surface for opening and analyzing a single PHD2 guide log. v2.0 enhancements:

- A new "Observations" panel in the inspector area, showing single-night observations for this log
- Annotation indicator on session inspector cards when annotations exist
- "Add note" affordance for annotating this session
- Help links from observation cards into the in-app help system
- (When rig profile is set) imaging-scale verdict indicator on the session stats strip

The document window does not need to know about the persistent store or the library — it produces analytical artifacts that flow into the store via a side-effect, but functions identically whether the library exists or not.

### 5.2 Library window (new)

A separate macOS `WindowGroup(id: "library")` scene, opened on demand from the menu bar (`Window → Library`, ⇧⌘L) via `@Environment(\.openWindow)`. The window is never auto-opened — macOS HIG reserves window-opening for explicit user action, and the throughlines' restraint posture makes unsolicited window-spawning especially wrong here. Discovery is handled via a TipKit popover (see §7.1).

**Layout:**
- Window chrome: standard macOS window with traffic lights, title "Library"
- Sidebar (~180px): rigs list, imaging scale display, guide setup display, annotations summary
- Main content area: scrollable, ~500–900px wide depending on window size
  - Header: time range tabs (Week / Month / Year / All), period summary
  - Hero metric cards: median RMS with imaging-scale ratio, best night, sub-pixel rate
  - Quality distribution bar (sub-pixel / at-resolution / over-resolution percentages)
  - Performance trend chart with annotation markers
  - PHD2 hygiene strip (Calibration Assistant freshness, GA recency, polar alignment status)
  - Active observations list (cross-night, expandable cards with evidence)
  - Recent nights list (with annotation indicators, click to open document)

The library is read-only — it doesn't modify logs. It does write annotations and rig profile data. The mockup at `[mockup-v2-reference]` is the visual target.

### 5.3 Help system (new)

A symptom-organized, illustrated reference document that lives in two places:
- **In-app help** via Apple Help (existing 1.x infrastructure, expanded content)
- **Deep links** from observation cards directly to relevant help topics

See section 8 for content structure.

### 5.4 MCP server (new)

An agentic surface exposing the library to MCP clients — primarily Claude Desktop and Claude Code, but any conformant MCP client. This is the load-bearing answer to the question *"can I just talk to Claude about my data instead of reading observation cards?"*

Conversational analysis is uniquely well-suited to multi-night astrophotography troubleshooting: the user already routinely shares PHD2 screenshots with Claude and gets useful feedback; an MCP server replaces screenshot-by-screenshot context-building with direct, structured access to the user's full library. Claude can spot the night-after-night patterns that the recommender catches *and* can answer the open-ended questions the recommender deliberately doesn't claim (throughline #1).

**Transport.** stdio MCP. This is what Claude Desktop and Claude Code expect, and stdio sidesteps every network-server entitlement question for a sandboxed macOS app.

**Architecture (see §12 Q9 for the open decision).** The server is delivered as a separate Swift binary (`ephemeris-mcp`) co-bundled inside the app at `Contents/Resources/ephemeris-mcp` (or similar). The user enables it from a Preferences pane; the app generates a Claude Desktop config snippet (and equivalent for Claude Code) the user copies into their MCP client config. The helper reads the same SwiftData store as the app via SQLite (WAL mode handles concurrent readers correctly).

**Tools (read-mostly).**
- `list_rigs()` — all `RigProfile`s
- `get_rig(id)` — full rig detail including imaging scale, guide configuration, notes
- `list_nights(rigId?, from?, to?, limit?)` — `NightRecord` rollups
- `get_night(id)` — full `NightRecord` including session stats, calibration, annotations
- `list_observations(rigId?, scope?, category?, severity?, dismissed?)` — typed `Observation` records
- `get_observation(id)` — full observation including evidence, contributors, suggested response, help-topic links
- `list_annotations(rigId?, range?)` — user-recorded events
- `add_annotation(nightId, categories, label, detail, isRigMutating)` — the one write tool, behind an opt-in toggle (see §9.5 below)
- `list_targets(rigId?)` — `TargetCluster`s with catalog matches
- `get_help_topic(id)` — help-system content (so Claude can quote the relevant help when answering)
- `get_aggregate_stats(rigId, range)` — computed rollups (median RMS, integration time, etc.)
- `get_ga_results(rigId, limit?)` — most recent `GAResult` entries

**Resources.** Each `@Model` type maps to a stable URI scheme: `ephemeris://rig/{uuid}`, `ephemeris://night/{uuid}`, `ephemeris://observation/{uuid}`, `ephemeris://help/{topic-id}`. Resources support both `resources/list` and `resources/read`; large series data (per-frame `GuideEntry` arrays) is exposed as resources rather than tool return values to keep tool responses lean.

**Discoverability.** A new Preferences pane "MCP Server":
- Master toggle: "Enable MCP server"
- Sub-toggle: "Allow writes (`add_annotation` tool)" — defaults off
- "Claude Desktop config" button: copies a JSON snippet to the clipboard with the absolute path to the helper binary
- "Claude Code config" button: same for `~/.claude.json` MCP server entries
- Status indicator: "Last connected: 12 minutes ago via Claude Desktop"

**Privacy.** Local-only. No outbound network. No telemetry. The helper binary speaks stdio only. The user explicitly opts in per-client by adding the config snippet — there's no auto-registration.

**Voice consistency.** The MCP server returns the recommender's existing `Observation` records verbatim — the differential voice (plural contributors, coaching responses, named PHD2 tools) survives the protocol boundary intact. Claude reads observations in the same shape the document window does, which keeps the rhetorical consistency the throughlines depend on.

### 5.5 Deferred surfaces (out of scope for v2.0, named for future reference)

- **Pre-flight surface** — "what's the state of my rig before tonight?" View showing calibration freshness, last GA, recent annotations, suggested checks. Probably v2.1.
- **Diagnostic flow** — guided troubleshooting wizard for users with active problems. Likely v2.2 or later.
- **Help-prep / forum-post export** — generate a structured forum post from a problem night with logs attached. Probably v2.1 or v2.2. (Note: the *Claude*-handoff portion of this is largely subsumed by the MCP server in §5.4; the forum-post export remains useful for Cloudy Nights / PHD2 forum threads where the audience isn't using Claude.)

---

## 6. The recommender engine

### 6.1 Engine structure

A single module that takes inputs and produces typed `Observation` records:

```
Inputs:
- GuideLog (parsed)              // for single-night observations
- [NightRecord]                  // for cross-night observations
- RigProfile                     // imaging scale, equipment context
- [Annotation]                   // user-recorded events
- [TargetCluster]                // pointing-aware grouping

Outputs:
- [Observation]                  // ordered by triage priority
```

The engine is stateless — given the same inputs, it produces the same outputs. No caching internally; let callers cache `Observation` records if needed.

### 6.2 Observation generation rules

Each observation type has a generator function that:
1. Computes a metric or pattern from inputs
2. Tests against a threshold appropriate to the rig profile
3. If the threshold is met, builds an `Observation` record with evidence, candidate contributors, and suggested response

**Generator catalog.** Each generator's `sourceAuthority` is declared explicitly — `phd2Manual` and `phd2Measurement` carry the most rhetorical force; `communityConsensus` and `ephemerisHeuristic` are softened.

PHD2-canon generators (`sourceAuthority: .phd2Manual` or `.phd2Measurement` or `.phd2BehaviorDocumented`):

- `guidingAssistantRecommendationObserver(...)` — when a recent `GAResult` exists, surface PHD2's recommended min-move RA/Dec, recommended exposure, backlash assessment, and polar-alignment error **verbatim**. **This is the highest-authority generator; its observations supersede any parallel Ephemeris computation.**
- `calibrationSanityAlertObserver(...)` — surfaces the four PHD2 calibration alerts by their canonical names: *Too Few Steps*, *Orthogonality Error*, *Questionable Rates*, *Inconsistent Results*. Pass-through with link to Calibration Review & Modification.
- `maxDurationLimitObserver(...)` — counts `RALimited` / `DecLimited` flags per session; when >5% of frames are rail-limited, surfaces an observation citing PHD2's Advanced Settings page and the specific Max RA/Dec Duration values to consider.
- `calibrationStaleness(...)` — calibration > 21 days = coaching, > 30 days = alert (post-fix corpus-calibrated). Cites Calibration Assistant.
- `calibrationOrthogonality(...)` — separate from age; orthogonality > 5° = pattern, > 10° = alert. Cites Calibration Assistant + Star Cross.
- `calibrationAngleShift(...)` — when calibration angles change ≥10° between adjacent calibrations, surfaces a state-change candidate (suggests annotation, cites Calibration Review & Modification).
- `variableExposureDelaysObserver(...)` — when `mountClass == .encoderBasedPremium` and the active profile shows short exposures + no variable delays, recommends enabling Variable Exposure Delays in Brain → Camera tab. This is the canonical PHD2 feature for the "monitor without correcting" pattern.
- `multiStarGuidingObserver(...)` — when frames consistently have ≥3 usable stars and multi-star mode is off, recommends enabling it.

Ephemeris-heuristic generators (`sourceAuthority: .ephemerisHeuristic` — softer voice, explicitly labeled):

- `imagingScaleRatio(...)` — when ≥50% of sessions exceed 1.0× imaging-pixel-scale, suggests binning consideration.
- `decPolarityBias(...)` — fires **only** when Dec polarity skew > 70% AND |Dec drift| > 0.03″/min AND polar-align estimate variance > 30% across last 5 sessions. Three-guard AND to prevent false-fire on healthy encoder mounts (see §6.5).
- `pulseRailRate(...)` — > 1% = watch, > 5% = pattern, > 15% = alert.
- `hfdCrossNightTrend(...)` — cross-night HFD trend across last 5-10 NightRecords (within-session HFD requires debug logs, out of scope; cross-night is feasible since header HFD is one value per session).
- `subQualityDiscrepancy(...)` — when sub-quality feedback exists and reports trailing while guide RMS is sub-pixel (Phase 9).
- `atmosphericConditionsProxy(...)` — combines star mass CV (>3× rig baseline) with altitude (<50°) and elevated RMS into a **don't-chase-this** observation. Coaching voice; explicitly tells the user this is conditions, not equipment.
- `dawnDegradation(...)` — pre-dawn RMS rise consistent across ≥3 of last 5 nights.
- `pointingDeltaStarCount(...)` — star count drop not explainable by galactic-latitude change.

Community-consensus generators (`sourceAuthority: .communityConsensus` — softest voice, labels explicitly as "community consensus, not in PHD2 docs"):

- `harmonicMountAlgorithmAdvisor(...)` — when `mountClass == .harmonicStrainWave` and exposures > 2s, suggests shorter exposures (~1s) and PPEC on RA citing harmonic-mount vendor PDFs and forum consensus. Never claims PHD2 endorses it.
- `oagGuideScopeDifferential(...)` — guide-scope flexure heuristics; clearly labeled as community wisdom.

### 6.3 Voice rules

Every observation conforms to the differential voice:

**Title**: Short, scannable, descriptive of the observation. *"Most sessions exceed imaging resolution"*. Not *"Your guiding is bad"*.

**Summary**: 1–2 sentences stating the measurement and key context. *"80% of sessions over 0.40″/px · 2×2 binning would put 87% sub-pixel"*.

**Evidence**: 3–5 bullet items, each a measurable fact. Numbers wherever possible. Confidence indicators (R², sample count) when applicable.

**Candidate contributors**: Always plural when present. *"Possible contributors: thermal contraction, dew accumulation, focus drift, atmospheric seeing collapse"*. Never *"this is caused by..."*.

**Suggested response**: Coaching, never imperative. References PHD2 tools by name when applicable. *"Worth running PHD2's Calibration Assistant on your next session — it slews to the optimum sky position, pre-clears Dec backlash, and reports cal quality automatically."*

### 6.4 Triage ordering

Observations are returned in this order (throughline 11):

1. `subQuality` (when feedback is available)
2. `opticalTrain`
3. `equipment` (state change candidates)
4. `phd2Hygiene`
5. `pattern`
6. `suggestion`

Within each category, ordered by severity (alert → pattern → coaching).

### 6.5 Threshold calibration strategy

A universal threshold like "RMS > 1″ = alert" is wrong twice: it false-fires on rigs that genuinely sit at 1″ baseline (small mounts in poor sites), and it false-passes for rigs that should be at 0.4″ (premium encoder mounts in dark sites). Throughlines #1 (restraint), #2 (anchor to imaging scale), and #8 (pointing context) all push the recommender toward **rig-relative thresholds, not universal ones**.

The calibration strategy has four layers:

**1. New rigs (first <10 `NightRecord`s): mount-class conservative defaults.**
Drawn from PHD2's Best Practices PDF where stated, community consensus where not. Each default carries the same `sourceAuthority` field as the resulting observations, so a new-rig observation honestly reads *"based on community consensus for encoder-based premium mounts, …"* rather than implying canon.

**2. Established rigs (≥10 `NightRecord`s): rig-baselined.**
The recommender computes per-rig median, p75, and p90 across the corpus. Generator thresholds tier against the rig's own distribution rather than absolute values:

| Tier         | Bound relative to rig distribution             |
|--------------|------------------------------------------------|
| `coaching`   | between p50 and p75                            |
| `pattern`    | between p75 and p90                            |
| `alert`      | beyond p90 OR > 2× rig median, whichever first |

The corpus (post-fix Edge-10m baseline, see §13) makes this concrete:
- Rig p75 RMS = 0.53″ → `coaching` tier starts here
- Rig p90 = 0.74″ → `pattern` tier starts here
- 2× rig median = 0.78″ → `alert` tier starts at the lower of the two

**3. State-change inference resets the baseline window.**
When §9.4 surfaces a candidate state-change event (calibration angle shift, baseline RMS step, etc.) *and* the user confirms it via annotation (`isRigMutating: true`), subsequent `NightRecord`s form a new regime for baseline computation. Pre-event sessions are retained but flagged as a separate population. The Edge-10m corpus's OAG-damage → fix → 100-point sky-model story is the canonical validation case for this rule (see §13.2).

**4. Mount-class also enforces an absolute floor.**
A rig-relative baseline can normalize a degraded state — if a rig has been bad for months, its own p90 is a low bar. The recommender layers absolute floors on top of the rig-relative tiers, indexed to imaging-pixel-scale:

| MountClass             | Hard alert when RMS exceeds…                |
|------------------------|----------------------------------------------|
| `.encoderBasedPremium` | 1.5× imaging-pixel-scale                     |
| `.standardGearMount`   | 2.5× imaging-pixel-scale                     |
| `.harmonicStrainWave`  | 3.0× imaging-pixel-scale                     |
| `.adaptiveOptics`      | 1.0× imaging-pixel-scale                     |

These floors reflect what the rig *should* be capable of and prevent a chronically-degraded rig's own normality from silencing the recommender. They have `sourceAuthority: .ephemerisHeuristic` (the multipliers are project judgment, not PHD2 doctrine) and are surfaced with softer voice than canon-cited observations.

---

## 7. The library scene (detailed)

### 7.1 Discovery

The library window is never auto-opened. macOS HIG reserves window-spawning for explicit user action, and throughline #1 (restraint) makes unsolicited window-opening especially wrong here.

Discovery is handled via **TipKit**: when the third `NightRecord` for a rig is ingested, a `popoverTip` anchored to the `Window → Library` menu item fires once — *"Ephemeris now has data from N nights — see trends in Library."* Tip state is persisted via TipKit's built-in storage; the tip auto-dismisses on first window-open or after 7 days, whichever comes first.

The library is always accessible via:
- Menu bar: `Window → Library` (⇧⌘L)
- Document window toolbar button (visible when the active document's rig has ≥1 NightRecord persisted)
- Spotlight (via the `IndexedEntity` integration on `RigProfile`)

### 7.2 Time range behavior

Tabs: Week, Month, Year, All. Each tab queries `NightRecord`s for the active rig within the range, computes aggregate statistics, and renders.

- Week: last 7 days
- Month: last 30 days
- Year: last 365 days
- All: from earliest record to today

When a range produces no data, the tab is disabled rather than showing empty state.

### 7.3 Performance trend chart

X-axis: per-night data points (Week/Month) or per-month aggregates (Year/All).
Y-axis: median RMS in arcseconds, with imaging-scale reference line at the rig's imaging pixel scale value.

**Annotation markers**: Vertical dashed lines at annotated nights with hover-revealed labels. Click to open the annotated night's document.

**Data point coloring**: Three-tier verdict colors (sub-pixel green / at-resolution amber / over-resolution coral) applied to each point based on its ratio to imaging scale.

**Performance budget.** Swift Charts hits a practical ceiling around 2–3K points per `Plot` before frame-rate degrades. The trend chart (potentially hundreds of nights × multiple series + annotation marks) and the existing combined-session view (up to 30K frames) both need:

- Vectorized `LinePlot` / `PointPlot` APIs (macOS 15+), **not** `ForEach { LineMark }` builders — the per-mark builder pattern is the single largest Swift Charts perf trap.
- LTTB (Largest-Triangle-Three-Buckets) downsampling off the main thread for any series exceeding 2K points. Cache the downsample keyed on `(sessionID, visibleDomainBucket)`; recompute only when the visible domain shifts by more than one bucket-width.
- `chartScrollableAxes(.horizontal)` + `chartXVisibleDomain(length:)` for the combined-session view rather than rendering the full domain.
- Maximum ~50 inline `RuleMark` annotations (annotation markers, settling bands, dominant-period rules) before clustering. Past 50, cluster adjacent annotations into a single mark and reveal individual labels on hover/zoom.
- No `.annotation(position:) { … }` SwiftUI views per data point — they're individually realized and the second-most-common perf trap.

### 7.4 Active observations panel

Cross-night observations only. Single-night observations stay in the document window. Each card shows:
- Severity-tier color dot
- Title + severity tag
- Summary (one-line)
- Disclosure caret to expand

Expanded card shows:
- Evidence list
- Suggested response
- Help-link to relevant topic
- "Discuss this" affordance (sendPrompt-style — eventually a Claude integration)

### 7.5 PHD2 hygiene strip

Three pills showing tool freshness for the active rig:
- Calibration Assistant: days since last cal, current orthogonality
- Guiding Assistant: days since last GA run (parsed from log INFO)
- Polar alignment: notes whether PHD2 PA tools have been used or whether the user relies on mount-side procedures (10Micron sky model, etc.)

Each pill is clickable and triggers a sendPrompt-style query to learn more about that PHD2 tool.

### 7.6 Recent nights list

Last 6 nights for the active rig in the time range. Each row:
- Date
- Annotation badge (if present) or hover-revealed "+ Note" affordance
- One-line summary or session count
- Hours of integration
- Median RMS
- Verdict pill (Sub-pixel / At-resolution / Over-resolution)
- Disclosure indicator

Click row → opens the original log in a document window (if file still exists) or shows persisted analytical artifacts (if log file was moved/deleted).

---

## 8. The help system

### 8.1 Posture

The help system is the educational layer that fills in everything the recommender deliberately doesn't claim. It's first-class in v2.0, not an afterthought. Users following an observation card's "learn more" link should land on a topic that gives them a complete, illustrated explanation of the relevant phenomenon.

### 8.2 Organization

**Symptom-organized, not topic-organized.** Users come at help from "my stars are trailed" or "my guide star keeps getting lost," not from "Calibration Tools → Drift Align → Step 2." The top-level navigation should reflect this.

**Cross-linked to PHD2 documentation.** Where PHD2 has authoritative documentation (Drift Align tutorial, Best Practices guide, Tools manual), Ephemeris's help links out to it rather than recreating it.

### 8.3 Topic catalog

The minimum viable topic catalog:

1. Reading your guide log — RMS, drift, calibration, settling
2. Pixel scale and imaging resolution
3. The image-scale ratio and what it means for round stars
4. Why your guide log doesn't tell the whole story (flexure, mirror flop, cable drag)
5. Differential flexure: what it looks like, how to detect, how to fix
6. Polar alignment fundamentals — the three PHD2 tools and when to use each
7. Calibration: what it is, why orthogonality matters, when to recalibrate, the Calibration Assistant
8. The Guiding Assistant: what it measures, how to use it, what to do with its recommendations
9. Guide algorithms: when defaults are right, when to consider alternatives
10. Aggressiveness, min-move, exposure: what they do and when to adjust
11. Backlash and how to address it
12. Common patterns and what they mean (oscillation, drift, settling failures)
13. Optical-train health: focus, dew, mirror flop, OAG vs guide scope
14. Setting up for the night: pre-flight checklist
15. When to ask for help and how to ask well

Each topic includes:
- Concept explanation
- Illustration(s) — SVG-friendly geometric concepts (axis decomposition, drift directions, oscillation patterns, calibration angles)
- Real-world examples drawn from forum patterns
- Cross-links to PHD2 documentation where appropriate
- Cross-links to other Ephemeris help topics
- "Where this shows up in Ephemeris" — pointer to relevant observation types

### 8.4 Delivery format

Apple Help bundle (existing 1.x infrastructure). HTML pages with inline SVG illustrations. Hosted in-app, indexed via `hiutil`, accessible via Help menu and ⌘? shortcut (existing).

Deep linking from observation cards uses `NSHelpManager.shared.openHelpAnchor(_:inBook:)` (preferred over raw `help:anchor=` URLs — the API handles same-anchor relaunch and navigation state more reliably on macOS 14+). Anchors are validated against the `hiutil`-generated index as part of release tooling so deep links never silently 404.

---

## 9. Annotations

### 9.1 Capture flow

Annotations are captured per-night via:

1. **Persistent `+` affordance on the night row** — a low-contrast `plus.circle` glyph visible on every row in the library's Recent Nights list (not hover-revealed — annotation is too central to throughline #3 "Know what the user did" to hide). Click opens an annotation **sheet** over the library window.
2. **Inspector affordance in the document window** — "Add note" control inside the session inspector for the open log. Annotations on the currently selected session are properties of that session and belong in the inspector alongside other session properties — not in a sheet that interrupts review.
3. **Library annotation summary** — a sidebar panel showing annotated nights and providing an entry point to add new ones (also opens the same sheet as #1).

### 9.2 Annotation modal

Structured form with:
- **Categories**: multi-select chips (Equipment / Calibration / Environment / Software / Free-text)
- **Label**: short text, displayed on chart and in row badges
- **Detail**: longer free-text
- **Date**: defaults to night's date
- **"This changed my rig"**: checkbox that triggers a follow-up rig profile update flow

### 9.3 Rig profile coupling

When `isRigMutating` is true, prompt the user to confirm or update rig profile values:
- Did the imaging scale change? (focal length / pixel size / reducer / binning)
- Did the guide configuration change? (OAG vs guide scope, guide camera)
- Should pre-event sessions be treated as a separate rig population for trend analysis?

### 9.4 State-change inference

Background analysis runs on every new ingest, looking for signal discontinuities:
- Calibration angle changes ≥10° between adjacent calibrations
- Multi-star baseline shifts ≥30%
- Median RMS step changes ≥40% across consecutive sessions
- Pixel scale changes (shouldn't happen mid-rig, suggests profile mismatch)

When detected, surfaces an `equipment` observation: *"Calibration angles shifted from X to Y between [date] and [date]. Possible state change — would you like to annotate?"*

---

## 10. Build sequence

The following phases are designed to ship incremental value. Each phase produces a working, useful version of the app — earlier phases don't depend on later ones for utility.

### Phase 0 — Distribution & auto-update foundation

Ships before any feature work because every subsequent phase needs a delivery channel. v2.0 is the first release that can update itself; 1.x users will need to manually install v2.0, after which they're on the Sparkle update track.

- Sparkle 2.x integrated via Swift Package Manager (the first 3rd-party dependency in the project — relaxing the Apple-frameworks-only posture explicitly and only for this purpose)
- **Info.plist keys**: `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval`, plus `SUEnableInstallerLauncherService = YES` (mandatory for sandboxed apps).
- **Sandbox entitlements**: two temporary mach-lookup exceptions are required for Sparkle's XPC helpers — `com.apple.security.temporary-exception.mach-lookup.global-name` with values `<bundleID>-spks` and `<bundleID>-spki`. Sparkle's `Installer.xpc` and `Downloader.xpc` are bundled and code-signed with the project's Developer ID. (If the existing `com.apple.security.network.client` entitlement is present, do **not** also enable `SUEnableDownloaderService` — Sparkle will use in-process download.)
- EdDSA signing keypair generated; private key stored outside the repo (via Sparkle's `generate_keys` → macOS Keychain); public key embedded in the bundle
- `Check for Updates…` menu item wired into the application menu (above About)
- Appcast generation integrated into release tooling: `generate_appcast` run against the GitHub Releases artifacts, producing a signed `appcast.xml` published as a release asset (or via GitHub Pages, depending on which the project standardizes on)
- Update settings UI: a minimal Preferences pane with "Automatically check for updates" toggle and channel selector if/when a beta channel is introduced
- Notarized, Developer ID–signed builds remain mandatory — Sparkle verifies both EdDSA signatures *and* relies on Gatekeeper for the installed package. The XPC services inside the bundle must be notarized alongside the host app or Gatekeeper rejects them on first launch.

**Deliverable:** a v2.0.0 build that, when installed manually, will discover and install every future v2.x release without user intervention.

### Phase 1 — Rig profile foundation

- `RigProfile` model + storage (JSON sidecar to start, SQLite later)
- Rig profile UI: create/edit per PHD2 profile name
- Imaging scale calculation from focal length, pixel size, reducer, binning
- First imaging-scale chip in the document window's session stats strip
- Inline prompt to configure rig when first opening a log without one

**Deliverable:** users can configure their rig once and see imaging-scale verdict on every session.

### Phase 2 — Recommender engine v1 (single-night)

- `Observation` schema and storage
- Engine module taking GuideLog + RigProfile and producing observation records
- Generator functions for single-night observations:
  - `imagingScaleRatio` — most sessions over scale → consider binning
  - `calibrationStaleness` — orthogonality and age
  - `decPolarityBias` — polarity skew analysis
  - `pulseRailRate` — max-pulse saturation
  - `hfdSessionTrend` — within-session HFD drift
  - `multiStarCount` — single-session optical signal
- Observation card UI in the document window inspector

**Deliverable:** every opened log produces single-night observations.

### Phase 3 — Persistent store

- SwiftData store at `~/Library/Application Support/Ephemeris/Library.store` (SQLite under the hood, managed by `ModelContainer`). The container is attached to the library `WindowGroup` only — `DocumentGroup` document windows do **not** share this container; ingest happens via a `ModelActor` that holds its own context against the same URL.
- `@Model` types: `RigProfile`, `NightRecord`, `Observation`, `Annotation`, `TargetCluster`, `GAResult`
- **Schema rules per §4**: every `@Relationship` declared optional, every attribute with a default value, ordered arrays stored as Codable-encoded `Data`, **no `@Attribute(.unique)` constraints** (uniqueness enforced by ingest `ModelActor`, not SwiftData). Designed to be CloudKit-clean even though sync is deferred to v3.
- Relationships use SwiftData's `@Relationship` with cascade delete rules (`RigProfile` → `NightRecord` → `Observation` / `Annotation`).
- `VersionedSchema` baseline (`SchemaV1`) + `SchemaMigrationPlan` scaffolding for future migrations.
- Auto-indexing on log open: parse → analyze → persist artifacts via a `ModelActor` so the document window stays responsive. Cross-context refresh between the ingest actor and the library window's `@Query` requires macOS 15 (one of the reasons for the deployment-floor bump per §3.0).
- Content hash deduplication (SHA-256 via `CryptoKit`) — check-then-insert inside a `ModelActor` transaction.
- CoreSpotlight indexing happens as a side-effect of insertion: each new `NightRecord` and `Annotation` is donated to `CSSearchableIndex.default()` via the `IndexedEntity` integration on the corresponding `AppEntity` types.

**Deliverable:** every opened log is silently persisted; nothing changes in the UI yet.

### Phase 4 — Help system foundation

- Help bundle expanded with the 15-topic catalog
- Symptom-organized landing page replacing existing Help index
- SVG illustrations for top-priority concepts (flexure, axis decomposition, drift, oscillation)
- Deep-link infrastructure from observation cards via `NSHelpManager.shared.openHelpAnchor(_:inBook:)` (not raw `help:anchor=` URLs)
- Anchor-validation pass in release tooling: every `relatedHelpTopicIds` reference is checked against the `hiutil`-generated index
- Cross-links to PHD2 documentation

**Deliverable:** help system is comprehensive and observation cards link into it.

### Phase 5 — Annotations layer

- `Annotation` model + storage
- Modal capture flow with structured categories
- Inline `+ Note` affordance on night rows (in document window for now, library to come)
- Display annotations in session inspector and on time-series chart
- Rig-mutating annotation flow with profile update prompts

**Deliverable:** users can record and review per-night events.

### Phase 6 — Library scene (basic)

- New `WindowGroup(id: "library")` scene with sidebar + main content (not `Window` — see §3.1)
- Rig selector in sidebar (driven by `@Query` against `RigProfile`)
- Time range tabs with `ContentUnavailableView` for empty ranges (not disabled tabs)
- Hero metric cards
- Quality distribution bar
- Performance trend chart honoring the performance budget in §7.3 (vectorized `LinePlot`, LTTB downsampling above 2K points)
- Recent nights list with persistent `+` annotation glyph (not hover-revealed — see §9.1)
- Click row → opens log document if file still exists; otherwise shows persisted artifacts
- TipKit `popoverTip` on the `Window → Library` menu item, fires on third `NightRecord` for a rig (not auto-window-open)
- App Shortcuts: *Open most recent log for [rig]*, *Show this week's trends for [rig]*

**Deliverable:** users with multiple nights can see a trend view.

### Phase 7 — Library scene (refined)

- Cross-night observations panel (new generator functions for cross-night patterns)
- PHD2 hygiene strip (CA freshness, GA recency)
- Annotation markers on trend chart with hover detail
- Annotation indicators on night rows
- State-change inference for equipment observations
- `GAResult` parsing from log INFO entries

**Deliverable:** library is fully realized as the cross-night surface.

### Phase 8 — MCP server

The library's schema and observation taxonomy stabilize at the end of Phase 7. Phase 8 makes them conversationally queryable.

- Standalone Swift binary (`ephemeris-mcp`) co-bundled at `Contents/Resources/ephemeris-mcp` in the app bundle
- Binary speaks stdio MCP; reads the SwiftData store via SQLite (WAL mode, read-mostly)
- Tools per §5.4: `list_rigs`, `get_rig`, `list_nights`, `get_night`, `list_observations`, `get_observation`, `list_annotations`, `add_annotation` (opt-in), `list_targets`, `get_help_topic`, `get_aggregate_stats`, `get_ga_results`
- Resources per §5.4: `ephemeris://rig/{id}`, `ephemeris://night/{id}`, `ephemeris://observation/{id}`, `ephemeris://help/{topic-id}` with `resources/list` + `resources/read`
- Preferences pane "MCP Server": enable toggle, write-allow sub-toggle, Claude Desktop config-snippet button, Claude Code config-snippet button, connection-status indicator
- Concurrent-access correctness: SQLite WAL mode + a tiny `INSERT OR IGNORE` write protocol for the `add_annotation` tool, so the app's `ModelContext` sees writes from the helper through SwiftData's history-tracking changes feed on next refresh
- MCP Swift SDK adoption decision (see §12 Q10) — JSON-RPC-over-stdio is small enough to hand-roll, but a maintained SDK avoids reimplementing the protocol surface
- App helper distribution: the binary is signed alongside the app under the same Developer ID, notarized as part of the same submission, and discovered by the helper-config UX via `Bundle.main.url(forResource:)`

**Deliverable:** users running Claude Desktop or Claude Code can ask conversational questions of their library ("what's been going wrong on my Edge 11 the last three weeks?") and get answers grounded in the same `Observation` records the document and library windows show.

### Phase 9 — Pointing/target awareness

- Compute galactic latitude per session from RA/Dec
- Cluster sessions by pointing similarity → `TargetCluster`
- Catalog matching (Messier + NGC offline lookup)
- Target-controlled observations: star pool normalized by galactic latitude, RMS comparison within targets
- "Targets" view or filter in library
- MCP server `list_targets` / `get_target` tools become populated (the scaffolding shipped in Phase 8 returns empty arrays until this phase)

**Deliverable:** observations become target-aware and confounds are controlled.

### Phase 10 — Sub-quality feedback loop

- One-tap per-night sub-quality marker (Round / Slightly elongated / Trailed / Mixed)
- Surface in document window post-session prompt
- New observation category: `subQuality` discrepancy detection
- Link from observation to flexure help topic when discrepancy exists
- MCP `list_observations(category: "subQuality")` exposes the new category

**Deliverable:** the differential-flexure trust gap is closed.

### Phase 11 — Forum-post export

The Claude-conversation path is owned by Phase 8 (MCP server). This phase remains useful for the forum-thread audience that isn't using Claude.

- "Share for help" affordance in observation cards and night views
- Generates structured Markdown summary: rig profile, recent nights, observations, suggested questions
- Forum-formatted variant for Cloudy Nights / PHD2 forum posts (BBCode where required)
- Copy-to-clipboard handoff (no claude.ai URL handoff — that flow is replaced by "ask Claude directly via the MCP server")

**Deliverable:** users can ask for help on forums with structured context.

---

## 11. Out of scope for v2.0

These are explicitly deferred. Not v2.0; possibly v2.x or v3.

- **Debug log parsing.** PHD2 debug logs (`PHD2_DebugLog_*.txt`) contain rich data (HFD per frame, exception throws, AutoFind sequences, mount comm latency) but require streaming infrastructure to handle 18MB+ files and aren't critical to the multi-night value proposition. Phase 3 architecture should leave room for debug log enrichment later but not block on it.
- **Pre-flight surface.** "What's the state of my rig before tonight" — useful but distinct enough from the library to deserve its own design pass.
- **Diagnostic wizard.** Guided troubleshooting flow for users with active problems. Different posture from the library; defer.
- **Multi-rig comparison.** "Compare my Edge 11 to my FRA 400." Interesting but not v2.0; pulls in design decisions worth resisting until usage patterns surface.
- **Cloud sync.** Multi-device library access. Local-first remains the v2.0 posture; cloud is a v3 conversation involving auth, conflict resolution, and a backend.
- **Real-time monitoring.** Connect to PHD2's event server during a live session. Out of scope; PHD2 itself does this well.
- **Auto-detection of equipment changes from external sources.** Reading EXIF from imaging frames, parsing NINA/SGP logs, etc. Annotations are user-driven in v2.0.
- **Anonymous benchmarking against other users.** "Other 10Micron + Edge HD 11 setups average X." Risky from a privacy and methodological standpoint; defer indefinitely.

---

## 12. Open questions

These are decisions to make during implementation, flagged here for visibility.

**Q1: Profile name reconciliation.**
PHD2 profile names mutate. When a log is ingested with a name that doesn't match any existing `RigProfile.currentName`, but does match a historical entry in `nameHistory`, should the engine auto-associate or prompt? Current proposal: auto-associate, with an audit log entry. Alternative: prompt on every mismatch.

**Q2: Schema versioning.**
What's the migration strategy for `Observation`, `Annotation`, etc. as the schemas evolve? Proposal: simple `schemaVersion` integer per record, migration code in a single `Migrator` module, run on app launch.

**Q3: Annotation timestamp granularity.**
Annotations are currently per-night. Should they support per-session or per-time precision? Use case: user makes a calibration change between sessions 3 and 4 of a 12-session night. Proposal: support optional time within night, default to session-level.

**Q4: Rig profile vs PHD2 profile multiplicity.**
Some users run multiple cameras through the same OAG (different filter configurations). Same PHD2 profile name; different effective rigs. Should we support multiple `RigProfile`s per PHD2 profile name? Proposal: yes, with user-selectable rig at log-open time.

**Q5: Help illustration fidelity.**
SVG illustrations for the help system can range from simple line drawings to detailed technical diagrams. What's the right level for v2.0? Proposal: simple line drawings, prioritizing clarity over polish; iterate on illustration quality post-launch.

**Q6: Cross-night observation surfacing in the document window.**
The library is the home for cross-night observations. But some are relevant during single-night review (e.g., "your calibration is 14 days old" while looking at tonight's log). Should the document window show a small subset of cross-night observations? Proposal: yes, but only the highest-relevance hygiene observations (cal staleness, GA staleness), not pattern observations.

**Q7: Backwards compatibility with existing 1.x logs.**
Users with existing logs already on disk should be able to bulk-ingest into the new library. Proposal: a "Scan a folder of logs" command available from the library window's File menu.

**Q8: Data export.**
Library data should be exportable. Format? JSON dump for portability, CSV per table for spreadsheet review? Proposal: both, accessible from a "Library → Export" menu.

**Q9: MCP server delivery and concurrency model.**
The MCP server in Phase 8 needs to read (and optionally write) the same SwiftData store as the app. Two viable architectures:

- *(a) Standalone helper binary co-bundled with the app*: `ephemeris-mcp` opens the SQLite file directly in WAL mode. Pros: sandbox-clean (no network entitlements), works whether or not the app is running, simplest user config (just point Claude Desktop at the helper path). Cons: schema knowledge duplicated across two binaries (or shared via a Swift package — *probably* the right factoring); concurrent writes from helper + app require careful WAL semantics and `INSERT OR IGNORE` discipline; the helper can't trivially trigger SwiftUI `@Query` refresh in the running app on writes (we'd need a `DispatchSourceFileSystemObject` watcher or a small Mach port ping).
- *(b) In-process server inside the app*: the running app spawns the MCP server thread. Pros: single source of truth, immediate `@Query` notifications. Cons: requires the app to be running for any Claude session to work, adds a network-server entitlement (`com.apple.security.network.server`) even for stdio because the helper has to be launched somehow by Claude — usually via a tiny launcher binary that forwards stdio to the running app via XPC, which is most of (a)'s complexity anyway.

Proposal: **(a)**, with the schema isolated into a shared Swift package both the app and helper depend on. Document the WAL-mode + history-tracking refresh pattern as part of the helper's design.

**Q10: Swift MCP SDK adoption.**
The MCP protocol over stdio is JSON-RPC — small enough to hand-roll in a few hundred lines of Swift, but doing so means owning protocol versioning. There's a community Swift MCP SDK (e.g., `modelcontextprotocol/swift-sdk`) that's improving. Adopting it would add a third 3rd-party dependency (after Sparkle) but save the protocol-implementation cost. Proposal: evaluate the SDK at Phase 8 start; adopt if the API surface and maintenance posture look sound, otherwise hand-roll. The cost of hand-rolling stdio JSON-RPC isn't large; the cost of staying current with MCP protocol evolution might be.

---

## 13. Development corpus

A real-world PHD2 guide-log corpus serves as the development reference, threshold-calibration source, and validation case for the recommender. As of writing the corpus is **Edge-10m, 59 guide logs, 630 sessions spanning 2025-12-22 → 2026-05-18** (≈4 months, ~247 hours of integration).

### 13.1 Privacy and version control

The full corpus lives at `~/Desktop/PHD2Logs/` — developer-local. It is **never committed to the public repository.** The 1.x project state established the precedent: *"No real-world logs are committed — they'd be large and contain timestamps that look like personal data"* (`PROJECT_STATE.md` §10). v2.0 retains this posture.

For committed test fixtures in `EphemerisTests/Fixtures/`, the team extracts small anonymized slices when a real-world edge case warrants a regression test. Anonymization: timestamps offset to an arbitrary epoch, profile names rewritten to generics, RA/Dec coordinates rotated.

### 13.2 The OAG damage → repair → sky-model regime change

The corpus contains a textbook state-change sequence spanning February–April 2026:

- **Pre-damage baseline (Dec 2025 – Feb 2026)**: median RMS 0.4–0.6″
- **OAG damage manifestation (Mar 1–4, 2026)**: median RMS spike to 2.5″, Dec drift to 0.18″/min, star mass collapse
- **First recovery attempt (Mar 11)**: new calibration at 3.7° orthogonality, RMS partially recovers to 0.45″ but optical signal still degraded
- **Continued damaged operation (April)**: 12.2° orthogonality calibration on Apr 15, irregular performance
- **Post-fix + new 100-point 10Micron sky model (Apr 24 onward)**: median RMS 0.39″, 0.8° orthogonality, 83% sub-pixel sessions

This regime is the canonical validation case for:

- **§9.4 state-change inference** — a simple 5-night rolling-mean step detector correctly identifies all four regime boundaries (RMS step at Mar 11, drift step at Apr 7, star mass step at Apr 18, orthogonality step at Apr 24) without parameter tuning.
- **§6.5 threshold calibration** — the pre-fix and post-fix populations must not be pooled; recommender baselines anchor to post-fix.
- **Throughline #10** ("equipment state is mutable and silent") — the OAG damage is invisible in the logs as a discrete event; only its consequences show up.

### 13.3 The post-fix subset as healthy-rig baseline

Sessions from 2026-04-27 onward (n=62 sessions, 13 nights) form the **healthy-rig baseline** the recommender's `.encoderBasedPremium` thresholds are calibrated against:

| Metric                    | Median   | p75    | p90    | Max    |
|---------------------------|----------|--------|--------|--------|
| RMS total (″)             | 0.39     | 0.53   | 0.74   | 1.06   |
| \|Dec drift\| (″/min)     | 0.004    | 0.008  | 0.033  | 0.16   |
| Dec polarity skew (%)     | 50       | 65     | 69     | 100    |
| Orthogonality (°)         | 0.8      | 0.8    | 0.8    | 0.8    |
| HFD (px)                  | 5.65     | 6.0    | 6.3    | 7.2    |
| Star mass CV (%)          | 4.8      | 10.5   | 31.2   | 58.8   |
| Sub-pixel RMS rate        | 83%      | —      | —      | —      |

These values seed the encoder-based premium defaults referenced in §6.5.

### 13.4 Variance-attribution finding

Pearson correlation of session RMS against every measurable factor (post-fix subset, n=62):

- **Star mass CV: r = +0.77** (dominant — atmospheric scintillation/transparency proxy)
- **Altitude: r = −0.65** (lower targets = worse, physics of atmosphere thickness)
- \|Hour angle\|: r = +0.61
- SNR median: r = −0.61
- HFD (header): r = +0.27 (weak — single header value doesn't capture intra-session seeing)
- Pier side: West 0.33″ vs East 0.44″ median (~25% asymmetry)
- **Within-night variance: 61%** of total
- **Between-night variance: 39%** of total

**Implication**: on a healthy premium rig, most RMS variance is conditions-driven (atmospheric stability) and target-geometry-driven (altitude/hour-angle), not equipment-driven. The recommender's primary job on such a rig is *explaining variance the user shouldn't act on* — throughline #1 in its purest form. This finding is what `atmosphericConditionsProxy` (§6.2) is designed to surface and what gives the throughlines empirical teeth.

### 13.5 Phase-by-phase corpus role

| Phase | Corpus role |
|-------|-------------|
| 1 — Rig profile foundation | Edge-10m profile: focal length 1960mm, ZWO ASI174MM (5.9μm pixels), guide pixel scale 0.62″/px, `mountClass = .encoderBasedPremium`, `hasHighPrecisionEncoders = true` |
| 2 — Recommender engine v1 | Post-fix subset tunes thresholds; pre-fix subset validates alert-tier behavior (the 2.5″ Mar 1–4 sessions are textbook `alert`-tier targets) |
| 3 — Persistent store | "Scan a folder of logs" bulk-ingest test case (§12 Q7); 59 logs with content-hash dedup |
| 5 — Annotations layer | The OAG repair date is the canonical multi-annotation test case: `equipment` + `calibration` + `software` (sky model) all on the same night |
| 6/7 — Library scene | Trend chart visualizes the 4-month regime story end-to-end; state-change inference fires on real data |
| 8 — MCP server | "Why did 2026-04-28 underperform?" should resolve via the same correlation logic Claude would otherwise reproduce from screenshots |
| 9 — Pointing/target awareness | Altitude correlation (r = −0.65) is the canonical target-aware-confound test |

## 14. References

- `PROJECT_STATE.md` — Current state of the 1.x app, parser internals, view layer
- `CODE_PROVENANCE.md` — Lineage analysis vs. phdlogview, licensing rationale
- PHD2 Manual landing — https://openphdguiding.org/manual/
- PHD2 Manual — Tools (every tool the recommender cites) — https://openphdguiding.org/man/Tools.htm
- PHD2 Manual — Guide Algorithms — https://openphdguiding.org/man/Guide_algorithms.htm
- PHD2 Manual — Advanced Settings (including Camera tab → Variable Exposure Delays) — https://openphdguiding.org/man/Advanced_settings.htm
- PHD2 Manual — Basic Use — https://openphdguiding.org/man/Basic_use.htm
- PHD2 Manual — Trouble Shooting — https://openphdguiding.org/man/Trouble_shooting.htm
- PHD2 Best Practices PDF — https://openphdguiding.org/Best%20Practices.pdf
- "Analyzing PHD2 Guiding Results" — https://openphdguiding.org/Analyzing_PHD2_Guide_Logs.pdf
- PHD2 EventMonitoring wiki (full INFO event taxonomy) — https://github.com/OpenPHDGuiding/phd2/wiki/EventMonitoring
- Pegasus NYX-101 Guiding Recommendations (harmonic-mount consensus reference) — https://pegasusastro.com/wp-content/uploads/2023/01/NYX-101-Guiding-Recommendations.pdf
- WarpAstron — Theory of autoguiding strain-wave HD mounts — https://bbs.warpastron.com/t/some-theory-of-autoguiding-strain-wave-hd-mounts/139
- Ephemeris GitHub — https://github.com/Raddock/ephemeris
- Mac Observatory article: "What Your PHD2 Guide Logs Actually Tell You (And What They Don't)" — companion editorial piece introducing the conceptual frame

---

*End of document.*

*This design document is meant to be revised. Each phase of implementation will surface decisions that warrant updating sections above. Treat the throughlines (section 2) as the most stable layer — they earned their place through the design conversation that produced this spec, and revising them should require equivalent rigor. Architecture and surfaces (sections 3–7) are stable but expected to clarify during implementation. The build sequence (section 10) is the most likely layer to be revised as priorities shift.*
