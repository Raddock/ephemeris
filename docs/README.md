# Mac Observatory — Documentation Standard

**Status:** Ratified July 2026. This is the canonical documentation standard for every Mac Observatory app.
**Purpose:** One defined set of documents per app, with a clear purpose, source, and maintenance policy for each. This exists so that documentation stays true to the code automatically (via Sidecar), so every app is consistent, and so any human or agent can find and trust the right document.
**Model:** Generalized from Strata's docs taxonomy and Ephemeris v2's state/roadmap/archive split — the two best-documented apps in the suite.
**Governance:** This file is copied identically into every app repo (`docs/README.md`). When the standard changes, it changes here first, then propagates. Sidecar treats this as the definition of what it maintains.

---

## The core principle

Every stale document in this suite fails the same way: a human wrote a version, build number, or feature status into prose, the code moved on, and nobody updated the prose. **The code (and its `pbxproj`) is always the source of truth. Prose must be kept in sync with it, not the other way around.**

Therefore every document is classified by *who keeps it true*:

- **Auto** — Sidecar regenerates it from the code. These hold code-derived facts. Humans should not hand-edit them; edits go stale and get overwritten.
- **Draft** — Sidecar writes a proposed version from the code; the owner reviews and tone-checks before it reaches humans. For anything with a human voice or external audience.
- **Manual** — Humans own the content. Sidecar never writes it; it may only lint for factual drift (e.g. a wrong build number), index it, or report on it. For judgment, priorities, and decisions.

## Church and state: one owner per file

Ratified July 2026, superseding mixed-ownership regions inside shared docs: **every document has exactly one owner, and owners never write into each other's files.** Single ownership per file holds by construction; it is not a mechanism that has to keep being gotten right.

- **Sidecar owns** (derived from code; regenerated; never hand-edited once the doc carries the header): `docs/CODEBASE_OVERVIEW.md`, `docs/PROJECT_STATE.md`, `docs/README.md` (standard propagation), the S2 cross-app overviews, and `docs/RELEASE_NOTES.md` / `docs/APP_STORE_RELEASE_NOTES.md` as Draft (Sidecar proposes; Andrew approves before it ships).
- **Claude Code owns** (derived from conversation; Sidecar never writes, only lints and reports): `CLAUDE.md`, `docs/ROADMAP.md`, `docs/FEEDBACK.md` and `docs/FEEDBACK_HISTORY.md`, `docs/decisions/`, `docs/RELEASE.md`, and `docs/CHANGELOG.md` (owner decision 2026-07-28: a changelog records human-meaningful change and intent, so release sessions write it as part of the change; Sidecar reads and cites it, never regenerates it).
- **Frozen** (nobody writes): `docs/archive/`.
- **The one documented exception:** `README.md` is Sidecar-owned but structurally mixes measured facts with marketing prose, so it keeps `draft:begin/end` human regions. This is the only file with mixed ownership, and it is deliberate.

The principle, plainly: **Sidecar knows what the code says; Claude Code knows what the conversation said.** If a fact cannot be produced by a command, it does not belong in a Sidecar-owned doc; it belongs with the owner who heard it. **Business facts are nobody's here:** pricing, store status beyond what the repo records, and marketing claims are not code-derived and do not belong in Sidecar-owned docs at all; they live on the product pages and in App Store Connect, and generated docs point there instead of copying them (a copied price is transcription rot with a currency symbol). Consequently PROJECT_STATE carries only re-derivable state; feedback-derived observations live in FEEDBACK.md, open questions and decisions in ROADMAP.md or docs/decisions/.

---

## The canonical set (10 per-app docs + 2 suite docs)

| # | Doc | Purpose | Generated from | Policy |
|---|-----|---------|----------------|--------|
| 1 | `README.md` | Public "what it is," requirements, build/install | Code + pbxproj (version, deployment target) + product page | **Auto** for facts; **Draft** for marketing copy |
| 2 | `CLAUDE.md` | Agent conventions, invariants, gotchas, doc map | Accumulated rules and hard-won lessons | **Manual**; Sidecar lints factual drift only (build numbers, architecture claims) |
| 3 | `docs/CODEBASE_OVERVIEW.md` | Architecture + file inventory, so a reader understands the app without reading the source | The code, stamped with the commit it was generated from | **Auto** |
| 4 | `docs/PROJECT_STATE.md` | What is true of the app *right now*: shipped surfaces, known limitations, in-flight work | Code + git + changelog | **Auto** (the "what's next" queue lives in ROADMAP, not here) |
| 5 | `docs/CHANGELOG.md` | What shipped when, dev-facing (Keep a Changelog format) | The release session that ships the change | **Claude Code-owned** (owner decision 2026-07-28); append-only; Sidecar reads and cites, never writes |
| 6 | `docs/RELEASE_NOTES.md` (+ `APP_STORE_RELEASE_NOTES.md` where App Store distributed) | Tester- and store-facing "what's new" | Distilled from CHANGELOG | **Draft** — Sidecar writes, owner tone-checks before it reaches humans |
| 7 | `docs/ROADMAP.md` | Every decided-but-unbuilt item, with its source (feedback ID, spec section); items deleted when shipped | Owner decisions | **Claude Code-owned.** Sidecar reports shipped-item matches and unresolved spec links; it never writes |
| 8 | `docs/FEEDBACK.md` (+ `FEEDBACK_HISTORY.md` archive) | The tester/user ledger and its archive | Humans (triaged against code, often from screenshots and user emails) | **Claude Code-owned** — the judgment doc. Sidecar may report changelog cross-links; moves to history are Claude Code's work, on Andrew's ask |
| 9 | `docs/decisions/` | Dated, append-only records: ADRs, audits, research, strategy, and their rationale (the "why") | Humans and review agents, with owner corrections | **Manual**, never regenerated; Sidecar may index them |
| 10 | `docs/RELEASE.md` | The mechanical release checklist (signing, notarization, appcast/App Store steps) | The actual release process | **Draft** once, then **Manual** |
| S1 | `docs/README.md` (this file) | Defines the standard: the canonical set, policies, and lifecycle rules | This document | Written once for the suite, identical in every repo |
| S2 | `MacObservatory/docs/{App}.md` | Cross-app product overview for the website, the dashboard, and agents | Distilled from each app's canonical docs | **Auto** — replaces the retired per-app `app_snapshot.md`; this is the artifact the dashboard serves over MCP |

---

## Supporting conventions (rules for Sidecar and for humans)

**The sync key (addresses the #1 failure).** Every **Auto** doc carries a header:

```
> Generated from commit <hash> at version <MARKETING_VERSION> / build <CURRENT_PROJECT_VERSION>, <date>.
```

Sidecar regenerates the doc when the project's `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` moves past what the header records. A doc whose header lags the pbxproj is, by definition, due for regeneration. A doc whose header is weeks stale *and* the version hasn't moved signals that Sidecar itself has stalled — a health signal worth surfacing.

**The per-doc handoff rule.** A doc is hand-maintained until it carries the `Generated from commit...` header. Only Sidecar ever stamps that header — never stamp it by hand, and never stamp it on a doc Sidecar did not generate. Once the header exists, the doc is machine-owned: hand-edits will be overwritten on the next regeneration, and maintenance duties end. Until then, maintain the doc normally, whatever its Auto/Draft classification says about its eventual owner. The handoff is therefore per-doc and self-announcing; no session needs to ask whether a doc has been taken over — the header is the answer. (Header form: a visible `> Generated from commit...` quote on internal docs, where freshness is useful to developers and agents; an HTML comment `<!-- Generated from commit... -->` on public-facing READMEs, where commit hashes read as noise to outside readers.)

**The archive rule (from Strata).** Superpowers plans/specs and SDD task files move to `docs/archive/` when their work ships. Archives and `docs/decisions/` are **frozen**: never updated, never regenerated. They are permanent provenance.

**AGENTS.md.** If a repo needs an `AGENTS.md`, it is generated from `CLAUDE.md` or symlinked to it — never hand-maintained separately. Hand-maintained twins diverge (Transit proved this: its AGENTS.md described a retired architecture as current).

**Retired doc type: `app_snapshot.md`.** These per-app snapshots went stale in every app that had one. They are retired suite-wide and replaced by the Auto-generated S2 cross-app overview. Do not create new ones.

**User-facing docs** (user guides, tooltip/help-string source, compiled Help Books) stay per-app and are **not** part of the parity core. They are release-gated, human-voice artifacts — Draft candidates later, but out of scope for automated maintenance for now.

**Provenance for Auto docs.** Because Auto docs are regenerated, humans must not store irreplaceable content in them. Session narratives, rationale, and decisions belong in `docs/decisions/` or archive (Manual/frozen), never in PROJECT_STATE or CODEBASE_OVERVIEW.

---

## Document lifecycle at a glance

```
Idea / decision      → docs/decisions/ (Manual, frozen)  and/or  ROADMAP.md (Manual)
In-flight work       → PROJECT_STATE.md (Auto, "in-flight" section)
Shipped              → CHANGELOG.md (Claude Code-owned, written with the change) + RELEASE_NOTES (Draft); ROADMAP item deleted;
                       design specs moved to docs/archive/ (frozen)
How it works now     → CODEBASE_OVERVIEW.md (Auto) + PROJECT_STATE.md (Auto)
User/tester reports  → FEEDBACK.md (Manual) → resolved items → FEEDBACK_HISTORY.md
Why it was done      → docs/decisions/ (Manual, frozen)
Cross-app summary    → MacObservatory/docs/{App}.md (Auto, served by the dashboard)
```

---

## Per-app conformance status (as of the July 2026 audit)

Each app is brought to this standard once (the "conform" pass) before Sidecar maintains it ongoing. Starting point per app:

- **Strata** — closest to standard; its taxonomy is the model. Minor fixes (build-number lines, README badges, dangling ROADMAP link), delete `app_snapshot.md`. Conform first; it's the template.
- **Laminar** — richest content, most drift. Repair and prune: delete superseded duplicates, regenerate CODEBASE_OVERVIEW to current version, fix the QHY status contradiction, split PROJECT_STATE (state vs session-narrative), promote the `Laminar v2/` folder into a real ROADMAP.
- **Meridian** — solid but no forward-looking doc. Add ROADMAP and a generated PROJECT_STATE; refresh README banner; verify SFSymbols against code.
- **Transit** — freshest, but rewrite/regenerate the wrong `AGENTS.md`; add a generated PROJECT_STATE; extract a RELEASE.md.
- **Ephemeris** — biggest structural gaps; brought to parity **separately and first among catch-ups** (it's the only open-source, public app). Add CLAUDE.md, CHANGELOG, RELEASE_NOTES, FEEDBACK; resolve the v2→main merge so process and docs agree.
