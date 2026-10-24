# Ephemeris feedback ledger

> The triaged record of user feedback. Ephemeris is a public open-source repo, so **intake happens in [GitHub issues](https://github.com/Raddock/ephemeris/issues)**: bug reports, feature requests, and parse-failure logs arrive there (README § Contributing asks reporters to attach the offending PHD2 log or a redacted excerpt). This file is the owner-triaged ledger built from those issues: what was accepted, what was deferred with reasons, what shipped. It is a Manual document per the documentation standard (`docs/README.md`); automation may cross-link entries to `CHANGELOG.md` but never writes the triage.

Format per entry, once items exist:

```
## FB-001 — short title
- **Source:** issue #NN (reporter), date
- **Report:** what was reported, in one or two sentences
- **Triage:** accepted / deferred (why) / declined (why)
- **Status:** open / shipped in X.Y (commit) / closed
```

## Open

## FB-001: ASIAir guide log reported as failing to open
- **Source:** email to the owner from an ASIAir user (not a GitHub issue), 2026-10-19, with one ASIAir log attached
- **Report:** Ephemeris would not open the "PHD2 compatible" `.txt` guide logs the ASIAir writes, and showed an error.
- **Triage:** accepted. The attached log opened in 2.0 without an error (1 calibration, 2 sessions, 0 malformed fields), so the reported error is not reproduced. The log did expose two parse gaps, fixed in 2.0.1: the banner has no PHD2 version number (`PHD2 version, Log version 2.5`), and the pointing line has no `RA = ` field, which dropped Dec, hour angle, and pier side. A reply asking for the exact error text, their macOS version, and how they opened the file was sent (drafted 2026-10-19; send date not recorded). Leading guesses, unconfirmed: a non-guide `.txt` from the ASIAir log folder, or macOS older than 15.
- **Status:** open (error unexplained); parse gaps shipped in 2.0.1 (`91de94a`). The reporter's log is not in the repo; `ASIAirFormatTests` uses a synthetic log in the same layout.

## Resolved

*None yet.*
