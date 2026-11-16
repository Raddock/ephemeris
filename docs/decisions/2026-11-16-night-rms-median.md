# 2026-11-16: Night RMS is the frame-weighted median of session RMS

**Status: on `main`, not yet released.** Owner decision, made while testing
the ASIAir import (`2026-11-16-asiair-rig-identity.md`).

**What happened.** After the ASIAir logs imported, some nights showed night
RMS and worst-session values far beyond anything a guided mount produces
(107″ night RMS, 1216″ worst session). The arithmetic was right: an
independent recomputation from the raw log matched to 0.1″. The logs record
guiding that wasn't holding the star:

- Starts that never settled: the star moving away steadily (about 15″/s on
  one 2025 night, with every RA correction at its 2500 ms maximum, which is
  what an untracked mount looks like) until PHD2 logged "Settling failed".
- Good guiding followed by a short runaway before "Star lost": one session
  held under 1 px for 8 minutes, then about 40 of its 837 frames drifted
  away, taking the session from under 1″ to 392″.

The night RMS was a frame-weighted mean of squared session RMS (quadrature
mean). Squaring makes it dominated by the worst sessions, so a few minutes of
runaway outweighed hours of good guiding.

**Alternatives measured** (customer ASIAir nights, then the owner's corpus):

| Night | Quadrature mean (old) | Plain mean | Median of sessions | Frame-weighted median |
|---|---|---|---|---|
| ASIAir 2025-07-03 | 107″ | 154″ | 1.53″ | 0.79″ |
| ASIAir 2025-08-10 | 29.3″ | 39.1″ | 6.04″ | 1.05″ |
| ASIAir 2026-10-23 | 0.64″ | 0.68″ | 0.69″ | 0.60″ |

- A plain mean of sessions is worse: every 12-second failed start counts as
  much as an hour of guiding.
- Excluding sessions where PHD2 logged "Settling failed" and never "Settling
  complete" fixes some nights but not the runaway-after-settling case, and
  misfires on ordinary PHD2 logs (below).

**Decision.** Night RMS is the frame-weighted median of per-session RMS
(`NightRMS.frameWeightedMedian`): half of the night's guided frames came from
sessions at or below it. It describes the typical guiding; the worst-session
figure keeps the failures visible. The ingestor and the single-night
recommender share the one function, so the document window and the Library
agree. As a side effect the stored attribute `medianRMSArcsec` is now
accurately named, so the queued SchemaV2 rename is dropped.

**Impact on the owner's corpus** (56 nights, PHD2 driven by NINA): 40 within
20% of the old value, 15 lower by more than 20%, 1 higher. The drops are
nights where a few sessions were much worse than the rest (2026-03-24:
1.87″ to 0.40″). One small night (2026-04-03, about 12 minutes of guiding)
reads 0.08″: ten of those minutes measured about 0.1″ in PHD2's own numbers,
so it is faithful, not a bug. Verdict chips and cross-night trends move with
it. Stored nights keep the old value until re-imported (re-import re-runs
analysis by design).

**Deferred: a per-night failed-attempt count.** The owner first agreed to
show "N of M never settled" on each night. Measured before building, it
doesn't hold up:

- Settle status misfires. In the owner's corpus 55 sessions never settled
  yet guided on normally (median 28 minutes at 0.77″, the longest about
  9 hours): a NINA settle timeout followed by good guiding is routine. In the
  ASIAir logs most never-settled sessions are 12-second aborted starts at
  about 1″, while the actual runaways (107″) mostly fall in another group.
- "Star farther from the lock position than the header's search region"
  separates the ASIAir runaways well (30 of 180 sessions, the worst ones),
  but fires on 45 of 710 sessions across 14 of 56 nights in the owner's
  corpus, mixing real trouble (2026-03-02, 30-minute sessions near 20″) with
  dithers larger than a 15 px search region.

Either needs thresholds calibrated against both corpora and a design pass.
Listed in ROADMAP.
