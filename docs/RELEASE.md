# Ephemeris release checklist

## One-time Sparkle setup — DONE (2026-07-07)

The EdDSA keypair was generated on 2026-07-07 with Sparkle's `generate_keys`.
The private key lives in the login Keychain of the signing Mac ("Private key for
signing Sparkle updates") — keep it safe, anyone with it can push updates to your
users. The public key is baked into `Ephemeris/Info.plist` → `SUPublicEDKey`, so
the updater now starts in normal builds. It still stays off inside test hosts,
and would go dormant again if the key were ever removed from Info.plist.

To sign releases from a different Mac, export/import the key first:
`generate_keys -x private.key` on this machine, `generate_keys -f private.key`
on the new one, then delete the exported file.

## Every release

> Status note (July 2026): active development lives on the `v2` branch, and `main` also carries unreleased post-1.0 work. Step 1's merge to `main` is the act that begins a release; until the v2 work is finished and merged, nothing past 1.0 is released. (`MARKETING_VERSION` already reads 2.0 with `CURRENT_PROJECT_VERSION` 1, and no v2 tag exists — the version was pre-bumped mid-development.)

1. Merge the working branch to `main`, confirm the full test suite passes
   (`xcodebuild test` for the app plus `swift test` in `tools/ephemeris-mcp/`),
   and tag `vX.Y` on `main` — releases and the appcast feed are cut from `main`.
2. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in the project.
   After the bump, run the Sidecar refresh (see CLAUDE.md, "After a version bump").
3. Archive with the Release configuration (Developer ID identity). The bundling
   phase builds the MCP helper universal and signs it with a secure timestamp.
4. Notarize and staple as usual; zip as `Ephemeris-x.y.zip`.
5. **Generate the appcast** over a folder containing the zip:
   ```
   .../SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast /path/to/release-folder
   ```
   This signs the archive with the Keychain key and writes/updates `appcast.xml`.
6. Create the GitHub release and attach **both** `Ephemeris-x.y.zip` and `appcast.xml`.
   The feed URL baked into the app is
   `https://github.com/Raddock/ephemeris/releases/latest/download/appcast.xml`,
   which always resolves to the newest release's asset — no separate hosting needed.
   (Caveat: because the feed always points at the *latest* release's appcast, keep
   each release's appcast.xml cumulative — `generate_appcast` does this automatically
   if you keep prior zips in the folder.)
7. Update the help book index if any help pages changed:
   ```
   cd "Ephemeris/Ephemeris Help.help/Contents/Resources/en.lproj"
   hiutil -C -a -f "Ephemeris Help.helpindex" .
   ```

## Notes

- `SUEnableAutomaticChecks` is deliberately **not set** in Info.plist. Sparkle
  only shows its standard consent prompt (second launch, user chooses) when the
  key is absent — setting it to either value suppresses the prompt and pins the
  behavior globally. Don't add the key.
- The end-to-end update path (appcast fetch → EdDSA verify → sandboxed install)
  has never been exercised against a published release. After the first 2.0
  release, verify it by publishing a trivial follow-up (or a local test
  appcast) before relying on it for anything urgent.
- v1.0 shipped without Sparkle, so 1.0 users will not auto-update — the 2.0
  announcement needs to reach them through release notes / the website.

## Store status and docs (added 2026-07-28; tightened same day after the Meridian 1.0.1 exercise)

When this app's store status changes (submitted, approved, released, rejected,
removed), in the SAME session and in this order:

1. **Update every canonical surface that asserts release state.** Known
   surfaces: `docs/PROJECT_STATE.md` (distribution and release identity,
   including any "awaiting" items), `README.md` (current status and
   distribution), `docs/CHANGELOG.md` (retitle in-development sections when
   they ship; add the release boundary), `docs/FEEDBACK.md` (dated status
   line if a submission thread lives there), and `CLAUDE.md` (implementation
   status). Then grep the repo for the previous status wording to catch any
   surface this list misses.
2. **Record only what is known.** Date-stamp in-flight status ("as of
   YYYY-MM-DD"). If a submission date or review detail is not known, write
   that it is unrecorded; never infer it.
3. **Only after the docs are corrected**, hand-run the Sidecar overview
   refresh on the Studio: `overview-check`, regenerate, `overview-validate`,
   `overview-commit`, `overview-push`. Regenerating against stale source
   restamps a stale claim with a fresh date, which is worse than leaving it.

Why this is manual for now: `docs/decisions/2026-07-28-store-status-staleness.md`.
A checklist fires only when a human runs it, and App Review acts
asynchronously; ASC-as-source remains the real fix.
