# 2026-11-16: ASIAir logs get a rig key built from the guide train

**Status: fixed on `main`, not yet released.** Feedback entry: FB-001.
Amends the "no profile name means no auto-ingest" decision in
`2026-10-23-asiair-log-support.md`.

**What happened.** After 2.0.1 shipped, ASIAir logs still would not import.
The owner obtained a customer's ASIAir log folder (11 `PHD2_GuideLog_*.txt`
files from July 2025 to November 2026, plus 8 `Autorun_Log_*.txt` files) and
ran it through the app's own parser and bulk importer in a test host.

**Root cause.** Parsing was never the problem: all 11 guide logs classify as
`.confirmed` and parse with 0 malformed fields (182 guiding sessions, 184,513 frames).
The failure was rig matching. ASIAir writes `Equipment Profile = ` with no
value in every header, and both Library paths key rigs on that name:

- Bulk import rejected every file with "no `Equipment Profile = …` line in
  header", so a folder of ASIAir logs imported nothing. This is very likely
  the error the FB-001 reporter saw.
- Opening a single log never auto-ingested, and the inspector showed neither
  the rig prompt nor the recommender, because there was no name to match.

The October fix tested parsing only, with a synthetic log, so it could not
see this.

**Decision.** When the profile line is present but blank (what ASIAir
writes), the rig key is built from the guide train in the same header:
`ASIAir · <camera> · <focal length> mm · <mount>`, for example
`ASIAir · ZWO ASI174MM Mini · 600 mm · ZWO000`. `RigIdentity` is now the
only place that turns a log into a rig key; the bulk importer, the document
window, the session detail view, and the inspector all call it.

- **Why these fields.** A PHD2 profile stands for a camera, a mount, and a
  guide scope. Camera and focal length separate this customer's five guide
  setups exactly. The mount is included because moving one guide scope to a
  different mount changes the mount class the recommender reasons about; one
  rig across two mounts would give wrong advice. Binning is left out because
  PHD2 users change it within one profile too.
- **Why the prefix.** The key is stored as `RigProfile.currentName`, the
  read-only matching key, so the UI needs to tell a built key from a real
  PHD2 profile name. `RigIdentity.isASIAirKey` checks the prefix, and the rig
  editor and inspector word their copy accordingly ("ASIAir guide train"
  instead of "PHD2 profile"). The prefix and format are now persisted data:
  changing either orphans existing ASIAir rigs.
- **Still measured, not inferred.** Every part of the key is copied from the
  log header. Where ASIAir writes `pixel size = unspecified` (this customer's
  ASI290MM Mini), the auto-created rig's guide pixel size stays 0 for the
  user to fill in. RA is still absent, so ASIAir nights still don't cluster
  by target.
- **Narrow trigger.** Only a present-but-blank profile line builds a key. A
  header with no profile line at all, or a blank one without a camera and
  focal length, still has no rig, as before.

**Autorun logs.** The ASIAir saves an `Autorun_Log_*.txt` beside each guide
log. Opening one used to give the generic "This file isn't a PHD2 guide log."
`PHD2LogSignature` now returns `.asiAirAutorunLog` when the `[Autorun|`
marker appears and no PHD2 marker does, and the open error names the file
and points to the `PHD2_GuideLog_` file from the same night. Bulk import
already skips these files by name.

**Verified.** The customer's folder, run through `LibraryBulkImporter` in an
in-memory Library: 11 imported, 0 errors, 5 rigs auto-created (one per guide
setup). All 8 Autorun logs classify as `.asiAirAutorunLog`. The customer's
files are not committed (public repo); `ASIAirFormatTests` covers the same
paths with synthetic logs, including an end-to-end bulk import.

**Not done (candidates for ROADMAP).** The Autorun log records the target
name and coordinates (`[Autorun|Begin] NGC 7380 Start`,
`Target RA:22h48m24s DEC:+58°8'53"`). Pairing it with the guide log by time
could restore target clustering and Messier matching for ASIAir nights. That
needs a design decision on how a second file enters the import, so it is
left for the owner.
