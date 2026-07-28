# 2026-07-28: Sidecar number-tokenizer gap, deliberately open

**Status: open by decision.** Not a defect to quietly fix; changing it is a
suite-wide call the owner makes.

**The gap.** Sidecar's Rule 1 validator ("every number in a generated doc must
trace to captured command output or canonical doc content") tokenizes numbers
with word boundaries that exclude digits embedded in alphanumerics. So a claim
like "8K output", "Wi-Fi 6E", or "M4 support" contributes no number token, and
the validator cannot catch it if it is unsupported. Surfaced by a Codex review
of the Stage 4 overview publish path, 2026-07-28 (finding 8).

**Why the current rule exists.** The boundary rule was an owner ruling that
closed a worse hole: without it, digit runs inside commit hashes ("c8f2cc9")
and identifiers donated tokens to the corpus, so a fabricated number could
"trace" to a coincidental substring of a hash. The tokenizer deliberately
trades a narrow miss (digits fused to letters) for the integrity of the whole
corpus.

**What changing it would cost.** Admitting letter-adjacent digits reopens the
hash-substring hole unless hashes and identifiers are stripped from the corpus
first, which means teaching the tokenizer what an identifier is across every
captured command's output format. Every existing doc and overview would need
revalidation, and false positives (file names, API names, "SwiftUI 6" style
idioms) would need per-case adjudication. The cost lands on every app at once,
which is why it is not a patch.

**Mitigation in place.** Product-style claims of this shape are rare in these
docs, the nightly's overview prompt requires distilling only what canonical
docs support, and supervised passes plus Codex reviews check prose that the
tokenizer cannot. The gap is recorded here so a future session neither
rediscovers it as a bug nor "fixes" it without weighing the hash-substring
hole it guards against.
