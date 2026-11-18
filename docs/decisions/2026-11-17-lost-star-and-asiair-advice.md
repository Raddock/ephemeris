# 2026-11-17: Lost-star stretches leave the recommender's input; ASIAir-aware advice

**Status: on `main`, ships in 2.0.4.** Owner decision (2026-11-17) to fix the
recommender before more ASIAir users meet it.

**What happened.** Verifying 2.0.3 against a customer's 11 ASIAir logs showed
the recommender giving wrong advice. ASIAir logs only reached it from 2.0.2,
so this was newly visible:

- Sessions where the mount stopped responding (the star ran 300 to 1,300 px
  from the lock position while every frame sent a maximum-length RA
  correction) were read as "Elevated RMS: likely atmospheric", and fed
  night-level observations ("first session 81× worse: cooldown", "RA guide
  rate misconfigured, 30×").
- "Likely atmospheric" also fired on ordinary sessions: its 0.7″ "elevated"
  bar was calibrated on a 0.62″/px guide train (about 1.1 px), and on the
  ASIAir's 3 to 7″/px guide scopes 0.7″ is a tenth of a pixel.
- "Multi-star guiding not enabled", citing PHD2's manual, fired on every
  ASIAir night because the ASIAir never writes the multi-star header field:
  an inference from a missing field.
- Advice named PHD2 dialogs (the Brain, the Guiding Assistant) that ASIAir
  users can't reach.

**Decisions.**

1. **Lost-star detection (`LostStar`).** A session's included frames end with
   at least 5 frames beyond the header's search region, the star's distance
   rises by more than one search region from the run's start to its end
   (median of 3 frames each, so one bad centroid can't qualify a steady
   offset), and guiding output was on throughout (the Guiding Assistant turns
   it off on purpose). Measured before shipping: 11 of 180 ASIAir sessions,
   all runaways; 1 of 710 sessions in the owner's NINA corpus (a star that
   drifted 15 to 40 px over 20 minutes with no corrections going out). An
   earlier draft that only required the star to stay past the search region
   flagged 19 NINA sessions that ended mid-settle after a dither with the star
   sitting still, so the "keeps moving away" condition is essential.
   Borderline cases stay unflagged: one ASIAir session whose star moved 46 px
   further against a 50 px region is not cut. Under-claiming is the safer
   error here.
2. **The analysis view.** `SingleNightContext` now gives generators the night
   with each lost stretch cut off, and drops sessions with fewer than 10
   frames left. The log as parsed stays available as `rawLog`: the star-shape
   observation reads it so it keeps agreeing with the Library chip (which
   predicts from stored, uncut session records), and the Guiding Assistant
   observation reads it so PHD2's results are always surfaced verbatim.
   Stored session statistics and night RMS are unchanged; they describe the
   log as recorded.
3. **"Guiding lost the star"** (`LostStarObserver`, Ephemeris heuristic badge,
   one per affected session). Measured first (distances, duration, frames
   with the star unmeasured, corrections sent on each axis), then what it
   usually means (corrections going out while the star keeps moving away
   points at a mount not acting on them; none going out points at guiding
   output paused), then what would tell the cases apart (the imaging
   software's log; on an ASIAir, the Autorun log). It says the stretch needs
   no guiding-settings change and is left out of other observations.
4. **"Likely atmospheric" bounds.** Silent above 5″ RMS (more than seeing can
   move a centroid), and "elevated" also needs half a guide pixel. On the
   owner's 0.62″/px rig half a pixel is 0.31″, so its behavior there only
   changes for sessions above 5″ (179 to 172 observations).
5. **Cooldown** counts only sessions with at least 30 included frames, so a
   3-frame failed start isn't "the first session". On the owner's corpus this
   compares each night's first real session: 3 observations become 6
   (1.8 to 4.4×), and 2026-03-17 drops from 26× to 3.0× because its first
   session was the lost-star one.
6. **ASIAir.** `GuideLog.isASIAir` (banner without a PHD2 version). Multi-star
   stays silent on ASIAir logs. Advice that names a PHD2 control gets one
   note that the ASIAir's settings live in its app and PHD2's dialogs aren't
   part of it. No ASIAir menu names are given: Ephemeris can't verify them.

**Codex review.** Four rounds, ten findings, all accepted and fixed with
tests (the fourth round: counting maxed corrections used `abs()`, which traps
on a damaged Int.min duration; it now compares magnitudes). First round: Guiding Assistant stretches and results must survive the
cut; corrections must be counted on both axes before saying guiding output
was off; a single spike must not qualify a steady offset; the stretch's
length must run to the session's end through unmeasured frames. Second
round: a non-finite or huge distance from a malformed row must not trap when
formatted; a run must not cross a merge sentinel in the combined-session
view; PHD2's calibration sanity alerts, like Guiding Assistant results, pass
through from the uncut log. Third round: a "nan" or huge timestamp (the
parser accepts both) must not trap when the length is formatted; and a merged
session carries only its first source session's header, so the detector now
declines merged sessions entirely rather than judge the last one by the
wrong search region (the combined-session view shows them uncut; the normal
view and the Library analyze each session with its own header).

**Not done.** "RA guide rate may be misconfigured" fires on 36 of the owner's
56 nights (ratios 1.5 to 4.5×) and on 4 ASIAir nights at similar ratios once
runaways are cut: a calibration question for every rig, not an ASIAir one.
Listed in ROADMAP.
