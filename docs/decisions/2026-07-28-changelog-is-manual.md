# 2026-07-28: CHANGELOGs are Manual, owned by Claude Code, read-only to Sidecar

**Decision (owner, 2026-07-28).** `docs/CHANGELOG.md` is a Manual doc in every
Mac Observatory app, permanently. Sidecar may read and cite it (overviews can
draw version and change facts from it) but must never regenerate or rewrite
it. The Sidecar sync-key header has been stripped and the doc removed from
Sidecar's regeneration allowlist and state.

**Why.** A changelog is a record of human-meaningful change and intent, not
something distillable from source. The proof came from Laminar 1.5.9: the
release session hand-appended a complete, correct 1.5.9 entry as part of the
change (correct behavior under the standing rule that docs update alongside
the code they describe), and Sidecar then spent six consecutive nights
raising DEFER because the doc no longer matched its recorded baseline. That
conflict recurs by design as long as two writers claim the same file. One
owner per file: release sessions write the changelog; Sidecar reads it.

**What Sidecar still does.** Reads `docs/CHANGELOG.md` for facts (the
`changelog_releases` capture) and cites it in generated overviews. Nothing
else. A hand-maintained changelog needs no sync-key header: it is current by
definition the moment a release session updates it.
