# 2026-10-23: ASIAir guide logs are a supported PHD2 variant

**Status: shipped in 2.0.1** (`91de94a`, tag `v2.0.1`). Feedback entry: FB-001.

**What happened.** An ASIAir user reported that Ephemeris would not open the
"PHD2 compatible" guide logs the ASIAir writes. Their attached log opened
without an error in the 2.0 code path: the signature gate accepted it as
`.likely` through the `Calibration Begins at` marker, and the parser read
1 calibration and 2 sessions with 0 malformed fields. The reported error was
not reproduced and remains open in FB-001.

**How ASIAir differs from PHD2** (from that log, compared with `sample_short.txt`):
banner `PHD2 version, Log version 2.5` with no version number; blank
`Equipment Profile =`; pointing line without `RA = ` and without Alt/Az; no
`Norm rates ... ortho.err.` line; `Calibration step = phdlab_placeholder` (an
unfilled template token, harmless); no `Guiding Ends` after the last session;
INFO lines limited to settling start/fail. Frame rows, calibration rows, and
the guide algorithm lines match PHD2.

**Decisions.**
- Treat ASIAir as a PHD2 variant in the existing parser, not a separate
  format: the differences are a handful of header lines, and the frame data
  is identical. The banner check accepts `PHD2 version,` as well as
  `PHD2 version ` (`PHD2LogSignature.isBanner`), and the pointing fields are
  matched independently with RA optional.
- What ASIAir omits stays empty, never inferred: no RA means no target
  clustering or Messier match for those nights; no profile name means no
  auto-ingest on open (the existing rule that ingest needs a rig profile
  match). Fabricating these would break the recommender's measured-versus-
  inferred honesty.
- The reporter's log is never committed (public repo, a private user's data).
  Tests use a synthetic log in the ASIAir layout.
- Release order for 2.0.1: tag only after the notarized build succeeded, so a
  failed notarization could not leave a tag on an unshipped commit. The signed
  build ran on the MacBook Air because the Developer ID identity and the
  Sparkle EdDSA key are not on the Mac Studio (checked 2026-10-23).

**Not done.** RA could only be recovered from the ASIAir's own data (it
writes none to the log), so cross-night clustering of ASIAir nights is out of
reach unless a future ASIAir firmware adds the field.
