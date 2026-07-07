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

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in the project.
2. Archive with the Release configuration (Developer ID identity). The bundling
   phase builds the MCP helper universal and signs it with a secure timestamp.
3. Notarize and staple as usual; zip as `Ephemeris-x.y.zip`.
4. **Generate the appcast** over a folder containing the zip:
   ```
   .../SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast /path/to/release-folder
   ```
   This signs the archive with the Keychain key and writes/updates `appcast.xml`.
5. Create the GitHub release and attach **both** `Ephemeris-x.y.zip` and `appcast.xml`.
   The feed URL baked into the app is
   `https://github.com/Raddock/ephemeris/releases/latest/download/appcast.xml`,
   which always resolves to the newest release's asset — no separate hosting needed.
   (Caveat: because the feed always points at the *latest* release's appcast, keep
   each release's appcast.xml cumulative — `generate_appcast` does this automatically
   if you keep prior zips in the folder.)
6. Update the help book index if any help pages changed:
   ```
   cd "Ephemeris/Ephemeris Help.help/Contents/Resources/en.lproj"
   hiutil -C -a -f "Ephemeris Help.helpindex" .
   ```

## Notes

- `SUEnableAutomaticChecks` ships as `false`; Sparkle shows its standard consent
  prompt and flips the preference per-user. Don't set it to `true` globally.
- v1.0 shipped without Sparkle, so 1.0 users will not auto-update — the 2.0
  announcement needs to reach them through release notes / the website.
