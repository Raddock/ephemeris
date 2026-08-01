# 2026-08-01: a release is a staleness key; Sidecar's version key alone is blind to it

**Status: fix built** in the Sidecar generator's sync-key check (the generator
lives outside version control on the Studio, so this record is the durable
account of the change).

**The gap.** Ephemeris 2.0 shipped 2026-07-31 (merged to `main`, tagged
`v2.0`, published to GitHub Releases), and a Sidecar refresh run the next day
reported "all docs current at 2.0/1; nothing to do" while `PROJECT_STATE.md`
and `RELEASE_NOTES.md` still described 2.0 as unreleased. Sidecar's app-doc
staleness check keyed on exactly one thing: the version/build in a doc's
generated header versus the pbxproj. The release did not bump the version
(docs were generated at 2.0/1 and the app shipped at 2.0/1), so from the
checker's view nothing had moved. Shipping is a state change with no version
delta, and a version-keyed check is structurally blind to it.

**Why this matters.** This is the same failure family as the store-status gap
(see `2026-07-28-store-status-staleness.md`): a fact restamped nightly as
current that quietly stopped being true. The difference is that store status
lives outside the repo, while a release tag lives in git, so this one is
fixable with a measured fact rather than a new upstream seam.

**The fix (built 2026-08-01).** Sidecar already captured `latest_tag` and
`latest_tag_date` in facts.json; the sync-key check now uses them. A doc whose
header version/build match the pbxproj is still marked REGENERATE when the
latest release tag is dated after the doc's generation date: the doc was
written in a pre-release world and must catch up. Verified against all five
apps: Ephemeris correctly flags `README.md` and `PROJECT_STATE.md` (generated
2026-07-19, tag 2026-07-31); the others report unchanged results. Once a doc
regenerates with a post-release header date, the check reads it as current
again, so the trigger converges after one regeneration.

**Residue.** The stale unreleased-2.0 prose in `PROJECT_STATE.md` and
`RELEASE_NOTES.md` was hand-corrected at the owner's direction on 2026-08-01
(commit `2770eb6`), ahead of this fix. `PROJECT_STATE.md`'s header still cites
pre-release commit `751e29a` until a Sidecar session performs the full
regeneration the checker now demands.
