# Ephemeris release checklist

## One-time Sparkle setup (before the first 2.x release)

1. **Generate the EdDSA keypair.** Sparkle's tools ship with the resolved package:
   ```
   ~/Library/Developer/Xcode/DerivedData/Ephemeris-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
   The private key lands in your login Keychain ("Private key for signing Sparkle updates").
   Keep it safe — anyone with it can push updates to your users.
2. **Paste the printed public key** into `Ephemeris/Info.plist` → `SUPublicEDKey`
   (replacing `REPLACE-WITH-GENERATED-ED25519-PUBLIC-KEY`). While the placeholder is
   present the app never starts Sparkle's updater at all — "Check for Updates…"
   shows disabled, and no appcast contact or log noise happens. The updater also
   stays off inside test hosts regardless of the key.

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
