# Observation Gap Analysis

*Maps every data signature the recommender can detect against the specific PHD2 control or tool that addresses it. Living document — update as new observations land. As of July 2026 every v2-scope gap identified here has shipped; the only open rows are the debug-log signatures deferred to v2.x.*

Format: **data signal → PHD2 lever (Brain tab / Tools menu) → coverage today**

The "lever" column matches PHD2's UI exactly: "Brain → Algorithms → RA aggressiveness" is the literal click path. This satisfies design throughline #4 (cite PHD2 tools by name) inside every `suggestedResponse`.

---

## Calibration health

| Signature | PHD2 lever | Today |
|---|---|---|
| "Too few steps" cal-sanity INFO line | Brain → Mount → **Calibration step (ms)** (lower); or Tools → **Calibration Assistant** | ✅ `CalibrationSanityAlertObserver` |
| Orthogonality > 5° between west and north legs | Tools → **Calibration Assistant** (slews to celestial-equator position) | ✅ `CalibrationOrthogonalityObserver` |
| > 30 days since last calibration | Tools → **Calibration Assistant** | ✅ `CalibrationStalenessObserver` |
| Step-change in orthogonality between adjacent nights | Tools → **Calibration Review and Modification**; recalibrate; add annotation | ✅ `CalibrationAngleShiftObserver` |
| Different cal residual per pier side | Recalibrate on each pier; Tools → **Cal Review and Modification** | ✅ `PierSideBiasObserver` |

## Polar alignment & drift

| Signature | PHD2 lever | Today |
|---|---|---|
| Dec polarity skew > 70% + drift > 0.03″/min | Tools → **Drift Alignment** / **Static Polar Alignment** / **Polar Drift Alignment** | ✅ `DecPolarityBiasObserver` |
| Trailed predicted, Dec-dominated drift | Same — polar alignment | ✅ `StarShapePredictionObserver` |
| Trailed predicted, RA-dominated drift | Brain → Mount → **RA guide rate**; check tracking rate / refraction model; PE training in mount firmware | ✅ `StarShapePredictionObserver` |
| Polar alignment error from GA verbatim | (PHD2 reports it; we surface it) | ✅ `GuidingAssistantRecommendationObserver` |

## Algorithm tuning

| Signature | PHD2 lever | Today |
|---|---|---|
| Algorithm doesn't match mount class | Brain → Algorithms → **RA / Dec algorithm** (Hysteresis / LowPass2 / etc.) | ✅ `AlgorithmMismatchObserver` |
| Lag-1 autocorrelation of corrections < -0.3 (oscillation) | Brain → Algorithms → **Aggressiveness** (lower) | ✅ `AggressivenessObserver` |
| Lag-1 autocorrelation > 0.3 with persistent drift (sluggish) | Brain → Algorithms → **Aggressiveness** (raise) | ✅ `AggressivenessObserver` |
| Sinusoidal residual at worm period | Brain → Algorithms → try **PredictivePEC**; or train mount PEC | ✅ `DataDrivenAlgorithmHintObserver` |
| Min-move > 1.5× seeing floor (missing motion) | Brain → Algorithms → **Min move**; Tools → **Guiding Assistant** | ✅ `MinMoveValidationObserver` |
| Min-move < 0.3× seeing floor (chasing seeing) | Brain → Algorithms → **Min move**; Tools → **Guiding Assistant** | ✅ `MinMoveValidationObserver` |
| GA-suggested min-move differs from active | Brain → Algorithms → **Min move** (adopt GA value) | ✅ `GuidingAssistantRecommendationObserver` |

## Mount-class-specific tuning

| Signature | PHD2 lever | Today |
|---|---|---|
| Encoder mount without VED | Brain → Camera → **Use Variable Exposure Delays** | ✅ `VariableExposureDelaysObserver` |
| Multi-star off when it could be on | Brain → Guiding → **Use multi-star guiding** | ✅ `MultiStarGuidingObserver` |
| Max-duration limit being saturated | Brain → Mount → **Max RA / Dec duration** | ✅ `MaxDurationLimitObserver` |
| Dec backlash > 3000ms (uni-directional needed) | Brain → Algorithms → **Dec guide mode** (north-only or south-only) | ✅ `GuidingAssistantRecommendationObserver` |
| Dec backlash 100–3000ms | Brain → Algorithms → **Enable Dec backlash compensation** | ✅ `GuidingAssistantRecommendationObserver` |
| Pulse-duration × guide-rate ≠ observed motion | Brain → Mount → **RA / Dec guide rate** (manual override); or check mount driver | ✅ `GuideRateValidationObserver` |
| No GA run in corpus | Tools → **Guiding Assistant** | ✅ `GAFreshnessObserver` |

## Scale & configuration

| Signature | PHD2 lever | Today |
|---|---|---|
| Guide profile values ≠ PHD2 header values | Edit rig profile (App → Rig Profiles…) | ✅ `GuideScaleMismatchObserver` |
| Guide arcsec/px outside 0.5–1.5× imaging arcsec/px | **Not a PHD2 lever** — hardware (different guide cam/scope/binning) | ✅ `GuideScaleMismatchObserver` |
| Guide pixel scale jumps between nights | Hardware/binning changed mid-corpus; add annotation | ✅ `GuideScaleMismatchObserver` |
| RMS > 1.25× imaging scale, symmetric (bloated round) | **Not a PHD2 lever** — accept (mount capacity floor), or reduce imaging scale (reducer / binning) | ✅ `StarShapePredictionObserver` |
| Axis-asymmetric RMS > 1.5× ratio (slightly elongated) | Brain → Algorithms → per-axis **Aggressiveness** / **Min move** | ✅ `StarShapePredictionObserver` |

## Star detection

| Signature | PHD2 lever | Today |
|---|---|---|
| Frequent star-lost events | Brain → Guiding → **Search region** (wider); **Star mass tolerance**; Brain → Camera → **no-star timeout** | ✅ `StarLostObserver` |

## Cross-night / mechanical

| Signature | PHD2 lever | Today |
|---|---|---|
| Rated trailed but data sub-pixel (differential flexure) | **Not a PHD2 lever** — mechanical (OAG mount, focuser stability, rotator clamp) | ✅ `SubQualityDiscrepancyObserver` |
| Best-to-worst session spread > 3× within a night (Mixed) | **Not a PHD2 lever** — transparency / wind / mid-session event; investigate annotations | ✅ `StarShapePredictionObserver` |
| First-hour-of-night elevated RMS | **Not a PHD2 lever** — thermal cooldown; OTA fan; longer pre-imaging warm-up | ✅ `CooldownSignatureObserver` |
| Atmospheric proxy (CV + altitude + RMS) | **Not a PHD2 lever** — accept; higher-altitude target next | ✅ `AtmosphericConditionsProxy` |
| Baseline RMS drifting upward across weeks | **Not a PHD2 lever directly** — investigate mount/equipment; prompt annotation | ✅ `BaselineRegressionObserver` |

## Debug-log only (deferred to v2.x per design §11)

| Signature | PHD2 lever | Today |
|---|---|---|
| Capture-error spikes (frame failures distinct from star-lost) | Brain → Camera; USB/cable | ⏳ Debug log |
| Mid-session setting changes | Don't change mid-session; investigate annotations | ⏳ Debug log |
| Saved cal parameters drift (RA rate / Dec rate) | Tools → **Cal Review and Modification** | ⏳ Debug log |

---

## Summary

- **Existing coverage**: 23 observation generators — every v2-scope row above is covered (the nine gaps identified in the June 2026 revision of this document all shipped in the gap-closure tier).
- **Debug-log scope**: 3 generators deferred to v2.x (see docs/ROADMAP.md).
- **No PHD2 lever (we educate, not prescribe)**: 5 scenarios — bloated stars at mount-capacity floor, mixed-conditions nights, cooldown, flexure, atmospheric. Surface as `.coaching` severity with help-topic links.

## PHD2 control surface reference

The "lever" column above uses these literal click paths so observations cite them verbatim:

**Brain dialog (Advanced Settings)**
- Global tab — diagnostic logging
- Camera tab — Variable Exposure Delays, no-star timeout, subframes
- Guiding tab — search region, star mass tolerance, multi-star, beep on lost star
- Algorithms tab (RA + Dec mirror each other) — algorithm picker, aggressiveness, hysteresis, min-move, max-duration limit; Dec guide mode (auto/north/south/off), Dec backlash compensation
- Mount tab — calibration step ms, RA/Dec guide rate, declination compensation, assume orthogonal axes

**Tools menu**
- Calibration Assistant
- Guiding Assistant
- Calibration Review and Modification
- Drift Alignment / Static Polar Alignment / Polar Drift Alignment
- Auto-Select Stars
- Manual Guide
- Star Cross Test
- Meridian Flip Calibration Tool
- Comet Tracking
- Lock Position
