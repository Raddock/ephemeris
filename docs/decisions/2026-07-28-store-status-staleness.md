# 2026-07-28: store status goes stale invisibly; ASC is the proposed source

**Status: gap documented, fix deliberately not built.** The fix is a
cross-machine session involving the MO Dashboard's App Store Connect sync and
its curated portfolio block; out of scope for the Studio-side sessions that
recorded this.

**The gap.** Store status ("in review as of 2026-07-28", "live on the Mac App
Store") is hand-maintained prose in each app's canonical docs, and the
published overviews distill it. It becomes wrong the moment App Review acts,
and nothing detects that: Sidecar's staleness check regenerates an overview
only when the pbxproj version/build moves or the canonical docs change since
the overview's header commit. A store approval changes neither. Strata's
overview saying "in App Store review as of 2026-07-28" will read as current
prose long after it stops being true.

**Why this matters.** This is structurally the same failure that produced
Meridian's TestFlight-only fiction: store status changed for every app in the
portfolio inside three weeks of July 2026 and the docs did not keep up,
because a fact with an authoritative upstream was being maintained by hand in
five places.

**Proposed direction (not built).** App Store Connect is the authority and
the MO Dashboard already syncs it. Studio-side Sidecar could consume that as
a measured fact (a capture in facts.json, same trust model as pbxproj
versions), making store status validate like any other number and making a
status change trip the overview staleness check. Designing that seam
(Mini-to-Studio data flow, offline behavior, which ASC states map to which
doc language) is the future session's work.

**Mitigation until then (manual, in the release checklist).** When an app's
store status changes (submitted, approved, released, rejected, removed):
update the canonical docs (PROJECT_STATE distribution and release identity,
README distribution) in the same session, then hand-run the overview refresh
on the Studio: `node generator/sidecar-generate.mjs overview-check <app>`,
regenerate, validate, `overview-commit`, `overview-push`. Date-stamp any
in-flight status ("as of YYYY-MM-DD") so staleness is at least visible to a
reader.
