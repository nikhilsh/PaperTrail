# OTA Distribution for PaperTrail

This repo now has a first-pass GitHub Actions workflow for Ad Hoc iOS distribution without TestFlight.

## Current intended flow
1. Import the Apple Distribution certificate from GitHub Secrets.
2. Import the Ad Hoc provisioning profile from GitHub Secrets.
3. Archive `PaperTrail` on a GitHub-hosted macOS runner.
4. Export an Ad Hoc `.ipa`.
5. Publish the `.ipa`, `manifest.plist`, and a tiny install page to a rolling GitHub Release tag named `adhoc-latest`.

## Secrets required
Set these in GitHub repository settings:

- `IOS_CERT_P12_BASE64` — base64 of the Apple Distribution `.p12`
- `IOS_CERT_PASSWORD` — password for that `.p12`
- `IOS_PROFILE_BASE64` — base64 of the Ad Hoc `.mobileprovision`
- `KEYCHAIN_PASSWORD` — temporary password used for the ephemeral CI keychain

## Encode locally
Use these commands on a trusted machine before pasting into GitHub Secrets:

```bash
base64 -i distribution.p12 | pbcopy
base64 -i PaperTrail.mobileprovision | pbcopy
```

If GNU `base64` is in use instead of the macOS one, use single-line output:

```bash
base64 -w 0 distribution.p12
base64 -w 0 PaperTrail.mobileprovision
```

## Important caveat: current Xcode project team ID mismatch
The checked-in Xcode project still contains an older `DEVELOPMENT_TEAM` value (`EHW7L3679R`) while the intended signing inputs for OTA are based on:

- Team ID: `635A559UST`
- Bundle ID: `nikhilsh.PaperTrail`

That means the workflow may still fail until the project signing settings are aligned. The workflow deliberately forces manual export options to reduce drift, but the project should still be cleaned up.

## Release URLs
The workflow publishes release assets under the tag `adhoc-latest`.

Expected URLs after a successful run:

- IPA: `https://github.com/<owner>/<repo>/releases/download/adhoc-latest/PaperTrail.ipa`
- Manifest: `https://github.com/<owner>/<repo>/releases/download/adhoc-latest/manifest.plist`
- Install page: `https://github.com/<owner>/<repo>/releases/download/adhoc-latest/index.html`

## Notes
- Ad Hoc installs require every target device UDID to be present in the provisioning profile.
- GitHub release asset URLs may or may not be ideal for iOS OTA over time; if Apple is picky, switch manifest hosting to GitHub Pages or another static host.
- This workflow is intentionally a first-pass skeleton. Expect one or two CI iterations to settle signing details.
