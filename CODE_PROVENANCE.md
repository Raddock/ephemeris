# Code Provenance Assessment

**Date:** 2026-04-25
**Reviewer:** Claude (automated engineering analysis — *not* legal advice)
**Original under review:** [agalasso/phdlogview](https://github.com/agalasso/phdlogview), GPLv3, © 2016–2018 Andy Galasso
**This project:** PHD2 Log Viewer (Swift/SwiftUI for macOS)

---

## Summary verdict

**Mixed, with the parser leaning derivative and the analysis code clearly independent.** The Swift codebase is *not* a line-by-line port — variable names, code expression, and concurrency model are all idiomatic Swift, and large parts (UI, statistics, FFT, multi-session merge, exporter, frequency analyzer) are independently developed using different algorithms and Apple frameworks instead of the original's GSL/wxWidgets stack. **However, the parser subsystem (`Parser/GuideLogParser.swift`, `Parser/HeaderParser.swift`, `Parser/InfoCoalescer.swift`, `Parser/NonMonotonicFix.swift`) is a behavioral reimplementation that closely mirrors `logparser.cpp` — same five-state machine, same magic strings, same edge cases, same INFO coalescing rules, same fallback strings, same "old log px/ms" heuristic, same AO direction aliases, same timestamp-jump-fixup algorithm using median of positive deltas. There is even an explicit comment in `InfoCoalescer.swift:50` referencing `logparser.cpp`.** No code is copied verbatim, but the behavioral fingerprint is strong enough that a careful licensing-aware reviewer could reasonably classify the parser as a derivative work under GPLv3's broader-than-copyright "based on" standard.

Confidence: **high** for the parser fingerprint findings, **high** for the analysis-code-is-independent findings.

---

## Evidence by subsystem

### 1. Log file parser

**Classification: (ii) Reimplemented from understanding — strong behavioral overlap with the C++ original.**

Files:
- C++: `phdlogview-original/logparser.cpp` (763 lines), `logparser.h` (224 lines)
- Swift: `PHD2 Log Viewer/Parser/GuideLogParser.swift` (284), `Parser/HeaderParser.swift` (128), `Parser/InfoCoalescer.swift` (95), `Parser/NonMonotonicFix.swift` (39)

Behavioral matches (all are functional choices, not file-format requirements):

| Behavior | C++ location | Swift location |
|---|---|---|
| Five-state machine (SKIP, GUIDING_HDR, GUIDING, CAL_HDR, CALIBRATING) | `logparser.cpp:531` | `GuideLogParser.swift:129` |
| Magic strings ("PHD2 version ", "Guiding Begins at ", "Frame,Time,mount", "Guiding Ends", "Calibration Begins at ", "Direction,Step,dx,dy", "Calibration complete", "INFO: ") | `logparser.cpp:29-43` | `GuideLogParser.swift:16-100` |
| Old-log px/ms heuristic: if rate < 0.05, multiply by 1000 | `logparser.cpp:299-302` | `Parser/HeaderParser.swift:71-72` (with comment "heuristic from logparser.cpp") |
| Treat `err == 0 \|\| err == 1` as included (`StarWasFound`) | `logparser.h:57-67` | `GuideLogParser.swift:197` |
| Fallback info text "Frame dropped" when err > 1 and info is empty | `logparser.cpp:670-672` | `GuideLogParser.swift:199` |
| Direction tokens including AO aliases: Left → west, Up → north | `logparser.cpp:410-419` | `Model/Calibration.swift` Direction enum init(token:) |
| RA/Dec sign convention (W → negative RA dur, S → negative Dec dur) | `logparser.cpp:200, 219` | `GuideLogParser.swift:185, 187` |
| XStep/YStep override radur/decdur for AO entries | `logparser.cpp:226-239` | `GuideLogParser.swift:189-192` |
| Convert declination from degrees to radians (`*pi/180`) | `logparser.cpp:641` | `Parser/HeaderParser.swift:28` |
| Header cursor tracking (device ∈ {mount, ao}, axis ∈ {X, Y}) for `Minimum move = ` attribution | `logparser.cpp:613-629` | `Parser/HeaderParser.swift:30-56` plus `HeaderCursorState` |

Differences (idiomatic Swift):
- C++ uses `nstrtok` over a 256-byte char buffer (`logparser.cpp:44, 105`); Swift uses a quote-aware `CSVTokenizer` with no length cap (`GuideLogParser.swift:253-269`).
- C++ uses `std::istream::getline` per line; Swift uses `text.split(whereSeparator: \.isNewline)`.
- C++ struct `GuideEntry` (`logparser.h:36-55`) has 17 fields in order `frame, dt, mount, included, guiding, dx, dy, raraw, decraw, raguide, decguide, radur, decdur, mass, snr, err, info`. Swift `GuideEntry` (`Model/GuideSession.swift:18-39`) has 19 fields in a different order (`frame, time, deviceKind, dx, dy, raRawDistance, decRawDistance, raGuideDistance, decGuideDistance, raDuration, decDuration, xStep, yStep, starMass, snr, errorCode, included, guiding, info`) — Swift adds explicit `xStep`/`yStep` storage rather than overwriting in place.
- Variable names: `raraw, decraw, dt, radur, decdur, mass, err` (C++) → `raRawDistance, decRawDistance, time, raDuration, decDuration, starMass, errorCode` (Swift). All renamed; none preserved.
- The Swift InfoCoalescer is a separate file with explicit rule documentation; C++ inlines it in `ParseInfo`.

### 2. RMS calculations

**Classification: (iii) Independently developed.**

- C++ (`AnalysisWin.cpp:59-86, 183-247`): single-pass **Welford-style** running variance via `LFit::data()`, where each datapoint updates `varx`, `covxy`, `vary` incrementally: `varx += (k * dx * dx - varx) / n`. Final RMS is `sqrt(varx)`, `sqrt(vary)`.
- Swift (`Stats/SessionStatsCalculator.swift:59-77`): **two-pass** algorithm — compute mean, then sum of squared residuals, then `sqrt(sumSq / n)`.

Both produce the same population standard deviation, but the code structures are unrelated. There is no Welford accumulator anywhere in the Swift code. Variable names (`varx`, `covxy`) appear nowhere in Swift.

A small **behavioral difference** also indicates independence: C++ peak (`AnalysisWin.cpp:196-199`) is `max(|raraw|)` — the largest absolute raw value, **not** subtracting mean. Swift peak (`Stats/SessionStatsCalculator.swift:33-34`) is `max(|value - mean|)` — peak deviation **from** mean. Same intent, different definition. A line-by-line port would not introduce this drift.

### 3. Drift calculation

**Classification: (iii) Independently developed.**

- C++ RA drift (`AnalysisWin.cpp:133-174`): a custom algorithm that sums RA corrections (`raguide` when `radur != 0`) across the session, finds first/last `Include`d entries, returns `(ra1 - ra0 - sum) / (t1 - t0)`. This deliberately backs out the corrections PHD2 made.
- C++ Dec drift (`AnalysisWin.cpp:93-131`): accumulates dec movements only when `prev_guided` was false (i.e., when guiding was disabled), then runs `LFit` regression on the accumulated y-values vs time.
- Swift drift (`Stats/SessionStatsCalculator.swift:36-39, 81-92`): naive least-squares linear regression of `raRawDistance` vs `time` and `decRawDistance` vs `time`, with no correction backout, no guiding-state gating.

These are completely different algorithms. The C++ version is more sophisticated (and arguably more correct in the presence of active guiding); the Swift version is a textbook regression. No line-by-line correspondence.

### 4. Frequency analysis (FFT)

**Classification: (iii) Independently developed.**

| Aspect | C++ (AnalysisWin.cpp:283-414) | Swift (Stats/FrequencyAnalyzer.swift) |
|---|---|---|
| FFT library | GSL `gsl_fft_complex_forward` (any-N complex) | Apple Accelerate `vDSP_fft_zripD` (radix-2 real) |
| Window | **Hamming**: `0.54 - 0.46 * cos(...)` (`AnalysisWin.cpp:372`) | **Hann**: `0.5 - 0.5 * cos(...)` (`FrequencyAnalyzer.swift:153`) |
| Zero-padding | None — uses N as-is | Pads to next power of 2 (`FrequencyAnalyzer.swift:158-163`) |
| Resampling | Akima cubic spline via `gsl_spline` (`AnalysisWin.cpp:32-57`) | Linear interpolation (`FrequencyAnalyzer.swift:99-123`) |
| Drift correction | Linear-fit subtract via `LFit` then `Line` functor | Custom `subtractLinearTrend` (`FrequencyAnalyzer.swift:125-140`) |
| Drop DC bin | Yes, omits f=0 (`AnalysisWin.cpp:389`) | Yes (`FrequencyAnalyzer.swift:72`) |
| Magnitude scaling | `4 / N` per UCLA reference | Normalised so max == 1 |

Both pipelines have the same overall shape (resample → detrend → window → FFT → magnitudes → period mapping), but every implementation choice differs. Different libraries, different windows, different padding strategies, different resampling math. The pipeline shape itself (resample uniformly, window, FFT, take magnitudes) is universal.

### 5. Calibration geometry

**Classification: Mixed — direction enum is (ii), display logic is (iii).**

- Direction parsing: both use the same five mount directions plus AO aliases (`Left=West`, `Up=North`). `Model/Calibration.swift` `Direction` enum mirrors C++'s `CalDirection` (`logparser.h:76-83`). This is dictated by the file format, but the enum shape is identical. Classified (ii).
- The C++ viewer doesn't compute orthogonality, RA/Dec rates, or pier-side metrics in the calibration view — it just renders the dx/dy plot. Swift's `CalibrationHeaderParser.swift` (133 lines) extracts a much richer set of fields (orthogonality from West-vs-North leg angles, ratePxPerSec, parity, pier side, hour angle, lock position) that the C++ viewer doesn't. Swift's `CalibrationGraphView.swift:60` adds concentric reference rings via a custom `chartBackground` overlay — there is no equivalent in the C++ paint code (`AnalysisWin.cpp` paint functions). Classified (iii).
- Plot color choices (red for E/W, blue for N/S, orange for backlash) — could plausibly originate from either source; this is a common convention in astronomy guiding software, not a fingerprint.

### 6. Settling-frame exclusion

**Classification: (iii) Independently developed (or rather, neither codebase has it).**

- C++: `Include` predicate (`AnalysisWin.cpp:88-91`) is *only* `e.included && StarWasFound(e.err)`. No time-window settling exclusion.
- Swift: filter (`Stats/SessionStatsCalculator.swift:11-15`) is `entry.included && !manualExclusionRanges.contains(entry.time)`. No automatic settling exclusion either; the `manualExclusionRanges` parameter is a Swift-side feature unique to this project (drag-to-exclude in the UI).

Neither codebase has automatic settling-frame exclusion as an independently-developed feature, so there's no fingerprint to match.

---

## Fingerprints found

These are the strongest indicators of behavioral derivation. Most are functional choices that could have been independently arrived at, but together they form a pattern consistent with the C++ source being used as a reference.

1. **Explicit credit comment** — `Parser/InfoCoalescer.swift:50` reads:
   > `/// Apply the three coalescing rules from logparser.cpp:`
   This is a developer-authored comment naming the C++ file as the source of three specific rules. The rules are then enumerated and implemented in Swift. This is the single strongest fingerprint; it's explicit acknowledgment that these rules were sourced from `logparser.cpp` rather than from the file format itself or from independent reverse-engineering of PHD2 logs.

2. **"Timestamp jumped backwards" string** — verbatim across both codebases.
   - C++: `logparser.cpp:511` (`insert_info(session, it, "Timestamp jumped backwards")`)
   - Swift: `Parser/NonMonotonicFix.swift:35` (`InfoEntry(frame: f, text: "Timestamp jumped backwards")`)
   This message is fabricated by the parser, not present in the log file. It is not user-facing copy that could be independently named; it's an internal marker. Verbatim copy.

3. **"Frame dropped" string** — verbatim across both codebases.
   - C++: `logparser.cpp:671` (`e.info = "Frame dropped";`)
   - Swift: `GuideLogParser.swift:199` (`if !included, (info?.isEmpty ?? true) { info = "Frame dropped" }`)
   Same situation: fabricated marker, verbatim text.

4. **`0.05` rate threshold** — exact numeric match for the px/ms vs px/sec heuristic.
   - C++: `logparser.cpp:299` (`if (mount.xRate < 0.05) mount.xRate *= 1000.0;`)
   - Swift: `Parser/HeaderParser.swift:71` (`if dev.xRate > 0, dev.xRate < 0.05 { dev.xRate *= 1000 }`)
   The Swift comment on line 70 even reads "Old logs stored rates in px/ms — heuristic from logparser.cpp."

5. **Median-of-positive-deltas timestamp fixup algorithm** — the *specific* algorithm of (a) collecting positive deltas, (b) taking median via `nth_element`-equivalent, (c) accumulating a corrective offset across remaining entries.
   - C++: `logparser.cpp:445-515` (`is_monotonic`, `FixupNonMonotonic`)
   - Swift: `Parser/NonMonotonicFix.swift:5-38` (entire file)
   Same algorithm, same approach, same outputs. Different code expression (Swift sorts and indexes; C++ uses `std::nth_element`), but the algorithmic identity is total.

6. **AO direction aliases (`Left` → west, `Up` → north)** — these are PHD2-specific conventions that the C++ parser handles as alternate tokens. They are not documented in any file-format spec outside the C++ source.
   - C++: `logparser.cpp:410, 416` (`if strcmp(s, "West") == 0 || strcmp(s, "Left") == 0`)
   - Swift: `Model/Calibration.swift` `Direction.init(token:)` recognizes the same set.
   This is a strong fingerprint because there's no published format document (PHD2 wiki only covers building the C++ viewer, not the file format). The only way to know about these aliases without reading the C++ is to find example AO logs.

7. **23/26-character string offsets implicit in noise-prefix stripping**.
   - C++: `logparser.cpp:340-343` strips `"SETTLING STATE CHANGE, "` (23 chars) and `"Guiding parameter change, "` (26 chars) from info lines.
   - Swift: `GuideLogParser.swift:240-243` does the same with `noisePrefixes` array.
   The exact list of two prefixes, in that order, with the same purpose (UI noise reduction), points to the same source.

8. **"DITHER" → strip from `, new lock pos` truncation rule**.
   - C++: `logparser.cpp:346-351`
   - Swift: `GuideLogParser.swift:244-246`
   Same edge case, same handling.

9. **Three INFO coalescing rules in the same order, fired under the same conditions** (already counted as #1 with the credit comment, but worth noting separately):
   - Rule 1 (repeats): same text, consecutive frames, increment counter.
   - Rule 2 (param replace): same `key=` prefix, same frame, replace.
   - Rule 3 (lock-pos→dither): SET LOCK POS followed by DITHER on same frame, replace.
   Both codebases implement these three rules and only these three rules. C++: `logparser.cpp:365-393`. Swift: `Parser/InfoCoalescer.swift:59-94`.

---

## Risk areas

- **Header parser.** While none of the Swift parser code is a literal copy, behavior is so close that a court applying the GPLv3's broad "work based on" standard could find the parser to be a derivative work — particularly given the explicit `logparser.cpp` references in code comments. The parser is the area most exposed.
- **The phd2-log-format skill.** A repository file at `.claude/skills/phd2-log-format/SKILL.md` explicitly says the C++ parser is the "authoritative spec" and instructs Claude (this assistant) to fetch `logparser.cpp` if questions arise. This documents the development methodology as "use C++ source as a spec," which a reviewer assessing provenance would find. It strengthens any "derivative" argument for the parser.
- **GuideEntry struct.** Although field order differs and names are renamed, the *set* of fields is essentially the union of C++'s `GuideEntry` (with the addition of explicit `xStep`/`yStep` instead of overloading `radur`/`decdur`). A reviewer could argue this is "translation of structure even though identifiers were renamed."
- **The `Parser/NonMonotonicFix.swift` algorithm.** This is the cleanest example of a non-trivial algorithm being reproduced. There is more than one way to fix non-monotonic timestamps (interpolation, drop-and-reframe, simple shift); both codebases pick the median-positive-delta approach with cumulative offset. Algorithm choice is a fingerprint.
- **None of the analysis subsystems.** The stats, drift, FFT, and calibration display code is solidly independent — different algorithms, different libraries, different conventions. These are very low risk.

---

## Recommendations

### Licensing

**Recommended: Release the entire app under GPLv3.** This is the lowest-friction, lowest-risk option:

1. The parser subsystem has strong behavioral fingerprints with `logparser.cpp` and an in-code comment crediting it. Even if not a strict derivative work in copyright terms, GPLv3's "based on" language is broad. Releasing under GPLv3 takes the question off the table.
2. The original is GPLv3, the user is following in its footsteps and serving the same community — license symmetry feels right.
3. Splitting the project under multiple licenses (GPLv3 for parser, MIT for everything else) is technically possible but creates packaging/distribution complexity that is rarely worth it for a small app.
4. GPLv3 is fully App Store compatible *for the developer's own apps* (you are the copyright holder, you can sign your own GPLv3 code; the issues with App Store and GPL only arise when others want to redistribute).

If you specifically want a permissive license (MIT/Apache/BSD), the path is to **rewrite the parser without consulting `logparser.cpp`**. That means working only from real PHD2 log files plus the public `.claude/skills/phd2-log-format/SKILL.md` document — but that doc itself was distilled from `logparser.cpp`, so it is also tainted. To do this credibly you would need to:
   - Delete `Parser/GuideLogParser.swift`, `Parser/HeaderParser.swift`, `Parser/InfoCoalescer.swift`, `Parser/NonMonotonicFix.swift`.
   - Delete `.claude/skills/phd2-log-format/SKILL.md` (the spec doc).
   - Re-write the parser from scratch using only sample log files as a reference. Don't read or even look at the C++ source.
   - Independently arrive at handling for: AO `Left`/`Up` aliases (won't be discoverable without an AO log), non-monotonic timestamps (won't trigger unless your sample data has a NTP jump), the SET LOCK POS → DITHER coalescing (PHD2-version-specific behavior), the 0.05 rate heuristic (won't trigger unless your sample data is from old PHD2).
   This is a significant amount of work and you'll likely miss edge cases that the C++ parser handles.

### Specific files to consider rewriting if cleaner provenance is desired

In rough order of "most fingerprinted" to "least":

1. `Parser/InfoCoalescer.swift` — has the explicit `logparser.cpp` reference. **Easiest to rewrite to remove credit comment.**
2. `Parser/NonMonotonicFix.swift` — algorithm fingerprint is total. Hardest to rewrite differently because the median approach is genuinely the right algorithm.
3. `Parser/HeaderParser.swift` — has the `logparser.cpp` comment on the rate heuristic. Easy comment to remove; algorithm itself is forced by the file format.
4. `Parser/GuideLogParser.swift` — fingerprints in the magic strings (forced by format) and the "Frame dropped" / state-machine choices.
5. `.claude/skills/phd2-log-format/SKILL.md` — the spec document explicitly written from `logparser.cpp`. Removing this would help the "independent reimplementation" argument.

### Suggested attribution language for the README (regardless of license)

The fair and honest framing, even under GPLv3:

> ## Acknowledgments
>
> This project is a Swift/SwiftUI rewrite of [phdlogview](https://github.com/agalasso/phdlogview) by Andy Galasso, originally implemented in C++ with wxWidgets. The original tool is the de facto standard log analyzer in the astrophotography community and informs this project's feature set, terminology, and core analysis workflow.
>
> The PHD2 log file format itself is not formally documented; the C++ parser in [agalasso/phdlogview/blob/master/logparser.cpp](https://github.com/agalasso/phdlogview/blob/master/logparser.cpp) was used as the authoritative reference for the log structure, header conventions, and edge-case handling (non-monotonic timestamps, AO direction aliases, INFO coalescing). Statistical analysis (RMS, drift, FFT) was implemented independently using Apple's Accelerate framework, with different algorithm choices (Hann vs Hamming window, vDSP real FFT vs GSL complex FFT, two-pass standard deviation vs Welford running variance, naive linear-regression drift vs PHD2's correction-aware drift).
>
> This project is released under the [GNU General Public License v3](LICENSE.txt) to match the upstream license.

This (a) gives clear credit, (b) makes the reference relationship explicit so users know what to expect behaviorally, (c) is honest about which subsystems are independent. It also ages well: if you ever decide to relicense, you have clear scope of what to revisit.

---

## Disclaimer

This is an engineering analysis based on a structural and lexical comparison of the two codebases. It is *not* legal advice. "Derivative work" under copyright law and "work based on" under the GPL are legal terms whose interpretation depends on jurisdiction, the specific code involved, and how a court (or community norms) would weigh similarity. If the licensing question is material to a commercial release or has a meaningful financial stake, consult a software-licensing attorney with the specific facts.
