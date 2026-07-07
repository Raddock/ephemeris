# Ephemeris (PHD2 Log Viewer) Code Audit — July 7, 2026

Read-only audit of the v2 branch. Two independent passes: Claude (assessed against the
macos-native-app-dev skill, with three deep read-only scouts) and Codex (13 findings via
the Codex plugin). Findings are written as consequence and stake for roadmap planning.
No code was modified. This is a map, not a work order.

## Overall health, in a paragraph

Ephemeris is in good shape, and notably it is the mirror image of Laminar. Laminar had
strong packaging around a structurally weak core; Ephemeris has a genuinely strong core
with risks concentrated at the edges. The foundations a designer can't see are the
healthiest part: modern APIs nearly everywhere (this codebase is what "finished the
migration" looks like), disciplined error handling with zero crash-bomb patterns, a
parser that is well built and well tested (about 358 test assertions, concentrated
exactly where correctness matters most, including tests against real log formats),
thoughtful empty and error states, and a sandbox/security posture that was clearly
designed rather than bolted on. The real risks cluster in three places: the app assumes
logs and libraries stay modest (the charts draw every single data point, so a normal
full night of guiding can make the app's core view sluggish or worse), the newest
features carry the newest risks (the MCP surface has two parallel implementations, an
unhardened HTTP request path, and an opt-in raw-database write mode), and the release
mechanics for auto-update are visibly unfinished (placeholder signing key, and a feed
URL that doesn't look like yours). None of this is rot; it's a healthy codebase whose
next problems are already visible.

---

## Critical findings

"Critical" here means: touches the core experience on normal data, or puts user data at
risk.

### 1. The charts draw every data point, and a normal night is 50,000 to 200,000 points

The main guide graph creates individual chart marks for every log entry (up to four per
entry), rescans the entire dataset on every mouse hover, and recomputes derived arrays
on every redraw with no caching and no thinning of points (`GuideGraphView.swift:148-195`,
`313-339`, `265-275`). Swift Charts degrades badly past a few thousand marks; a full
night of guiding is 10 to 100 times past that. This is not an edge case: a whole-night
log is the normal input for this app.

- **What it costs:** the app's signature view gets sluggish to unusable exactly when a
  user brings their real data, and it silently caps how big a "night" the app can honor.
- **Urgency:** high, this is the core interaction.
- **Fix size:** days (decimate to screen resolution before plotting, cache the derived
  arrays; TrendChartView already shows the point-budget pattern, it just wasn't applied
  to the guide graph).

### 2. The optional "allow writes" MCP mode has a second program writing directly into the app's live database

The standalone helper (`tools/ephemeris-mcp`, installed for Claude Desktop) reads the
app's SwiftData store by reverse-engineering its private SQLite table layout, and when
the user opts into writes (`EPHEMERIS_MCP_ALLOW_WRITES=1`), it inserts annotation rows
directly, including manually bumping Core Data's internal ID counter
(`LibraryStore.swift:618-785`), while the app may have the same file open. The code is
careful (opt-in flag, transaction with rollback, busy-handling), but Apple gives no
guarantee that an external writer won't confuse Core Data's bookkeeping, and a schema
rename in a future version will silently break the helper while the app keeps working.

- **What it costs:** worst case is a corrupted library (the user's entire history); the
  likelier, quieter cost is the helper breaking invisibly on the first schema change.
- **Urgency:** medium-high now, urgent the moment SchemaV2 is planned.
- **Fix size:** days (keep the helper read-only and route writes through the app, or add
  tripwire tests that fail loudly on schema drift).

### 3. The embedded MCP server trusts the request size a client claims

The HTTP handler accumulates request data until it reaches whatever `Content-Length` the
client declared, with no upper bound and no rejection of nonsense values, no rate
limiting, and no tests on any of this (`MCPConnectionHandler.swift:30, 158-163`). Any
local process (while the server is enabled) can make the app eat memory until it dies.
Softening context: the server is off by default, loopback-only at the socket level, and
the DNS-rebinding Host-header defense is genuinely well done.

- **What it costs:** a crashable hole in the one network door the app has, on a headline
  feature.
- **Urgency:** high because the fix is disproportionately cheap.
- **Fix size:** hours (cap the body size, reject bad lengths, add the missing tests).

---

## Worth doing

### 4. A headline stat is mislabeled

The night-quality number stored and exposed as `medianRMSArcsec` is actually a
frame-weighted quadrature mean (`LibraryIngestor.swift:61-72`; the code comments say so
honestly). The math chosen is arguably better than a median, but the label lies. For an
app whose entire value is "trust these numbers," a user who checks the arithmetic loses
trust in everything else. *Verified against the code.* Cost: credibility. Urgency: high
because it's cheap. Fix: hours (rename or relabel).

### 5. Auto-update cannot ship as-is, and one detail looks wrong

Sparkle is correctly built and deliberately dormant: `SUPublicEDKey` is still the
`REPLACE-WITH-...` placeholder, so the updater never starts (intentional guard,
`EphemerisApp.swift:58-64`). But `SUFeedURL` points at `github.com/Raddock/ephemeris`,
which does not match the macobservatory identity: verify whether that's a stale template
value. Cost: users on v2.0 won't hear about v2.1 until this is finished; a wrong URL
would point updates at a repo you may not control (a real supply-chain concern).
Urgency: blocking for release, irrelevant until then. Fix: hours.

### 6. Rig profiles are bookkept twice

Canonical rig data lives in a JSON file (`RigProfileStore`); a mirror copy lives in
SwiftData (`RigProfileEntity`) so nights can reference it; syncing is manual
(`LibraryWindow.swift:79-84`), and git history shows a past drift bug (`c388958`).
Annotations have a similar double life. Cost: "I edited my rig in one window and the
other window disagrees"; every rig feature must remember to sync both. Urgency: medium.
Fix: days (pick one owner).

### 7. Two MCP implementations kept in agreement by hand

The embedded server (5 read-only tools) and the standalone helper (13 tools plus the
write mode) are separate codebases over the same data. One parity round has already been
fixed; the tax recurs on every tool change. Cost: Claude gives different answers
depending on which connector is installed. Urgency: medium. Fix: days to share a core or
week+ to consolidate; cheap start is a parity test diffing the two catalogs.

### 8. Big-file handling has one guarded door and one unguarded one

Document open refuses files over 500 MB with a good error, but parses on the
document-open path (a large-but-allowed file can stall the window) and holds multiple
copies in memory. The bulk importer has no size cap at all
(`LibraryBulkImporter.swift:118`), and its ModelContext accumulates objects across a
whole import run. Cost: one absurd file in a scanned folder can spike memory; huge
single logs stall the open. Urgency: low-medium (typical PHD2 logs are a few MB).
Fix: a day or two.

### 9. No database migration plan exists yet

The schema is versioned and CloudKit-clean (good foresight), but the container is built
with no `SchemaMigrationPlan` (`EphemerisLibrary.swift:23-24`, deferred to "Phase 3").
Shipping any schema change without it means existing users' libraries fail to open.
Cost: nothing today, everything the day it's forgotten. Urgency: gate on the roadmap,
before SchemaV2. Fix: days.

### 10. The parser turns garbage into zeroes silently

A corrupt numeric field in a guide row becomes 0 rather than being counted as suspect
(`GuideLogParser.swift:200-220`), so a damaged log can read as "perfect guiding" and
feed the recommender wrong. Cost: rare, but poisons stats invisibly. Urgency:
low-medium. Fix: hours to a day (count coercions, flag the session when nonzero).

### 11. Zero accessibility labels

Roughly 90 interactive controls and rich charts, none with VoiceOver labels (tooltips
exist but don't count). Cost: excludes users; weakens App Store standing. Fix: a day or
two.

### 12. Test coverage is strong exactly where it's strong, and absent exactly where the new risk is

Parser, stats, merger, rig model: excellent (~358 assertions). MCP server (the
network-facing code): zero tests. Views and chart state: zero. Bulk importer and the
Claude config installer: zero. Cost: findings 3, 7, and 13 have no tripwires. Fix: days
for the high-value slice.

### 13. The Claude config installer rewrites config files it doesn't own, without a backup

`ClaudeConfigInstaller.swift` is carefully written (validates JSON first, refuses
malformed files, merges rather than replaces, writes atomically), but it fully
reserializes `~/.claude.json` (which holds unrelated state) and keeps no backup copy.
It also contains a hardcoded fallback path to a personal dev checkout (lines 107-108).
Cost: low probability, high annoyance. Urgency: low. Fix: hours (write a `.bak`, strip
the dev path for release builds).

---

## Minor

- **Localization has no foundation** (~123 hardcoded strings, no String Catalog). Zero
  cost while English-only; a slog to retrofit later.
- **The FFT recomputes on the view-render path** when toggling options; bounded data, so
  a stutter, not a hang.
- **UTF-8-only file decoding** rejects a legacy log with odd-encoding characters; real
  PHD2 logs are almost always fine.
- **Styling leftovers:** 2 deprecated color modifiers, 16 fixed font sizes (mostly
  About), 3 hardcoded colors that won't adapt to dark mode.
- **Tests split across two frameworks** (Swift Testing and XCTest), mid-migration;
  harmless.
- **No custom file type declared** for PHD2 logs (claims plain text, gates by content
  sniffing; works, but no "Open with Ephemeris" default for `.txt` guide logs).

---

## Where Codex and Claude disagree

1. **Sparkle's health.** Codex's verdict described the updater as "HTTPS + EdDSA-gated,"
   implying done. It isn't: the signing key is a placeholder (updater never runs) and
   the feed URL points at an unexpected org. Claude treats this as a pre-release
   blocker; Codex didn't flag it. The most consequential gap between the two reviews.
2. **Chart severity.** Codex rated no-downsampling "worth doing"; Claude rates it
   critical because a full night is this app's normal input, not a stress test.
3. **The request-size hole.** Codex rated it critical; Claude notes it's gated behind an
   off-by-default, loopback-only server. Full agreement on fixing it immediately.
4. **Blind spots, both directions.** Codex uniquely caught the mislabeled median
   (verified) and articulated the no-auth-token tradeoff crisply. Codex missed the
   Sparkle problems, the rig-profile double bookkeeping, the config-installer backup
   gap, and the accessibility/localization dimension. Both passes independently agree
   on: charts, MCP duplication, the dual-writer risk, importer guards, parser
   zero-coercion, and the test gaps.

---

## Ranked shortlist

1. **Harden the MCP request path** (finding 3). Hours. Cheapest fix relative to stake;
   closes the app's only network door. Add the missing MCP tests in the same sitting.
2. **Relabel the median-that-isn't** (finding 4). An hour. Trust in the numbers is the
   product.
3. **Downsample the guide charts** (finding 1). Days. The single most user-visible
   improvement in this report.
4. **Finish the Sparkle release mechanics** (finding 5), scheduled against the release
   date: real key, verified feed URL.
5. **Settle the MCP write story** (findings 2 and 7 together). Days. Either the helper
   stays read-only and writes go through the app, or the dual-writer stays and gets
   schema-drift tripwires plus a catalog parity test. Deciding this before SchemaV2
   forces finding 9's migration plan onto the calendar at the right moment.

Everything else (rig-profile unification, importer guards, accessibility, localization)
can be pulled by the roadmap rather than pushed by risk.

Closing observation: Laminar's audit was about rescuing the core; this one is about
protecting a good core while its newest limbs (MCP, library, updates) harden. Ephemeris
rewards polish investment immediately; Laminar needs structural work before feature work
pays off.
