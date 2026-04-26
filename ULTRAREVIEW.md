# `/ultrareview` Findings — Pre-Launch Hardening Pass

**Run date:** 2026-04-25
**Scope:** 47 files changed, 1,641 insertions, 279 deletions across 3 hardening commits.
**Branch:** `main` vs `origin/main`.

---

## Verbatim findings

### 1. `bug_002` — Hover/jump filter overshoots — drops parser-flagged frames as well as sentinels
**Severity:** normal
**File:** `Ephemeris/Views/GuideGraphView.swift:264-273`

The new `activeEntry` filter at `GuideGraphView.swift:265-273` uses `.filter(\.included)` to skip the NaN boundary sentinels from `GuideSessionMerger`, but it overshoots: `GuideEntry.included` is also `false` for any frame the parser flagged with `errorCode > 1` (star lost / frame drop, see `GuideLogParser.swift:221`). As a result, hovering or jumping (from the inspector's Events card) to a dropped frame silently snaps the rule to a neighbouring included frame, and the explicit `if !entry.included { Text("Excluded") }` branch in `HoverCard` (lines 475-477) is now unreachable dead code. Fix by filtering on `!entry.raRawDistance.isNaN` (or `!entry.dx.isNaN`) instead — that skips only the boundary sentinels and preserves hover-on-dropped-frame readouts.

**Step-by-step proof:** A session with three consecutive frames where frame 101 has `errorCode = 2` (`included = false`). Pre-PR: `activeEntry` returns frame 101, `HoverCard` shows the orange "Excluded" badge, pinned rule sits exactly on frame 101. Post-PR: `activeEntry` filters out frame 101, then minimises distance over {100, 102}; rule snaps to the wrong frame, hover card shows that wrong frame's RA/Dec/SNR, and the "Excluded" badge never appears.

---

### 2. `bug_019` — INFO frame collides with boundary sentinel — events drawn in the inter-session gap
**Severity:** normal
**File:** `Ephemeris/Stats/GuideSessionMerger.swift:59-67`

The sentinel insertion in `mergeUsingDates` (and `mergeBySequencing`) increments `maxFrame` *before* the existing `info.frame += maxFrame` shift below it, so any INFO entry that the parser tagged with frame=0 (PHD2's typical 'Settling started' that lands between the column header and the first data row) collides with the sentinel's frame number after merging. `entryTime(forFrame:)` then returns the sentinel — whose time is the inter-session gap midpoint — so settling bands paint across the empty wall-clock gap and inspector click-to-jump lands the selection rule in the dead-space between sessions. Fix by shifting `info.frame += maxFrame` *before* the sentinel increment (the cleanest option), or by skipping non-included entries in `entryTime(forFrame:)`.

**Step-by-step proof:** Two sessions, A frames 1-3 ending at t=10s, B starts 600s later with frames 1-3 and a `Settling started` INFO at frame=0. After merge: sentinel appended at frame=4, time=305s (in the gap). Session B's frame=0 info shifted to frame=4 — exactly the sentinel's frame. `settlingBands` calls `entryTime(forFrame: 4)`, finds the sentinel at t=305s. The eventual `Settling complete` resolves to t=605s. The band is drawn from t=305s to t=605s — painting the entire 590-second wall-clock gap as settling.

---

### 3. `merged_bug_001` — Boundary sentinels surface in CSV export, frame counts, and diagnostic chart
**Severity:** normal
**File:** `Ephemeris/Stats/GuideSessionMerger.swift:105-122`

Boundary sentinels (`included = false`) leak into three downstream consumers that don't honor the contract `makeBoundaryEntry`'s doc-comment promises ("keeps it out of stats, scatter, hover lookup, and CSV exports"):

1. **`CSVExporter.frameDataCSV`** (`Stats/CSVExporter.swift:87`) iterates `session.entries` unfiltered, so multi-session "Frame data (CSV)" exports get rows with the literal string "nan" in every numeric column (Swift's `String(format: "%.4f", .nan)` → `"nan"`), breaking the help docs' RFC 4180 / spreadsheet-portable promise.
2. **`GuideSession.frameCount`** returns `entries.count` (`Model/GuideSession.swift:35`), so two merged 100-frame sessions display as "200 / 201" in `SessionDetailView.framesText` and "200 included · 1 excluded" in `SessionInspectorView.framesValue`, falsely implying PHD2 dropped frames.
3. **`DiagnosticGraphView`** (`Views/DiagnosticGraphView.swift:51-58, 102-105`) plots sentinels as legitimate points with `starMass = 0, snr = 0` (sentinels are 0 here, *not* NaN), drawing a sharp V-dip to zero at every session boundary on the star-mass and SNR sub-charts; hovering near the boundary reads "Star mass: 0" / "SNR: 0".

Each call site needs a `.filter(\.included)` (mirroring the `GuideGraphView.activeEntry` change this PR already made), or `makeBoundaryEntry` could populate every numeric field with `.nan` so consumers fail loudly instead of silently producing wrong numbers.

---

### 4. `bug_017` — Scatter ring labels omit unit suffix in pixels mode
**Severity:** nit
**File:** `Ephemeris/Views/ScatterInsetView.swift:215-225`

Ring labels in the scatter inset omit the unit suffix in pixels mode. The format `String(format: "%.1f%@", r, unitsSuffix == "\"" ? "\"" : "")` only emits the suffix when it's already an arc-second quote, so pixels-mode rings render as bare "0.5", "1.0" instead of the "0.5px", "1.0px" the help docs added in this PR explicitly promise. Drop the ternary and use `unitsSuffix` directly:

```swift
let labelText = String(format: "%.1f%@", r, unitsSuffix)
```

---

### 5. `bug_011` — Dead helper: `SessionInspectorView.sectionHeader` is no longer referenced
**Severity:** nit
**File:** `Ephemeris/Views/SessionInspectorView.swift:53-61` (definition referenced as line 138 in the report)

The private `sectionHeader(_:systemImage:count:)` helper at `SessionInspectorView.swift:138` is no longer referenced. The `InspectorCard` refactor in this PR moved every `Form/Section { … } header: { sectionHeader(…) }` to `InspectorCard`, which builds its own header inline. Per CLAUDE.md guidance against carrying unused helpers, this ~16-line method can be deleted.

---

### 6. `bug_009` — BOM trim claim mismatches `CharacterSet.whitespaces`
**Severity:** nit
**File:** `Ephemeris/Parser/PHD2LogSignature.swift:60-65`

The comment on `PHD2LogSignature.swift:57` claims "Some logs may have leading whitespace or BOM", but `CharacterSet.whitespaces` is Unicode category Zs + U+0009 and does **not** include U+FEFF — so the trim-then-prefix check on line 59 will not strip a BOM. Practical impact is essentially nil (PHD2 itself never emits a BOM, and a BOM-prefixed log still classifies as `.likely` via the marker fallback on lines 65-73, which `GuideLogDocument.init` accepts identically to `.confirmed`), but the comment overpromises. Suggest either dropping the BOM clause from the comment, or extending the trim set to include U+FEFF.

---

### 7. `bug_010` — Doc-comment refers to non-existent `GuideLogErrorView`
**Severity:** nit
**File:** `Ephemeris/Document/GuideLogDocument.swift:24-27`

The new `GuideLogLoadError` enum's doc-comment claims errors are "Surfaced to the user via `GuideLogErrorView` (see ContentView)", but no such view exists anywhere in the codebase (verified via grep — only match is the comment itself). Errors actually surface through SwiftUI's default `DocumentGroup` alert via the `LocalizedError` conformance. Either implement `GuideLogErrorView` for a custom presentation as the comment promises, or update the comment to describe actual behavior.

---

## Severity summary

| # | ID | Severity | Subsystem |
|---|---|---|---|
| 1 | bug_002 | normal | GuideGraphView |
| 2 | bug_019 | normal | GuideSessionMerger / event lookup |
| 3 | merged_bug_001 | normal | CSV / frame count / diagnostic chart |
| 4 | bug_017 | nit | ScatterInsetView |
| 5 | bug_011 | nit | SessionInspectorView |
| 6 | bug_009 | nit | PHD2LogSignature |
| 7 | bug_010 | nit | GuideLogDocument |
