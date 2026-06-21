# Sentry dSYM Upload Configuration

## Overview

This document describes the Sentry dSYM upload integration for PaperTrail iOS ad-hoc builds. The GitHub Actions workflow now automatically uploads debug symbols to Sentry after each successful build, enabling symbolicated crash reports and stack traces.

## What Was Changed

### 1. GitHub Actions Workflow (`ios-adhoc-ota.yml`)

Added two new steps after the "Export IPA" step:

1. **Install sentry-cli** - Downloads and installs sentry-cli v2.40.0
2. **Upload dSYMs to Sentry** - Uploads debug symbols with source context

The workflow uses the `--include-sources` flag to enable [Sentry Source Context](https://docs.sentry.io/platforms/apple/guides/ios/data-management/debug-files/source-context/), which allows Sentry to display code snippets alongside stack traces.

### 2. Debug Symbol Generation (Already Configured)

The Xcode project already has the correct configuration for Release builds:
- `DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"` ✅
- dSYMs are automatically generated during the Archive step
- Located at: `$ARCHIVE_PATH/dSYMs/` (e.g., `build/PaperTrail.xcarchive/dSYMs/`)

## Required GitHub Secrets

You need to add **three new secrets** to your GitHub repository:

### 1. `SENTRY_AUTH_TOKEN`

**What it is:** A Sentry authentication token with permission to upload debug files.

**How to create it:**
1. Go to [Sentry Organization Settings → Auth Tokens](https://sentry.io/settings/auth-tokens/)
2. Click "Create New Token"
3. Name: `GitHub Actions - PaperTrail dSYM Upload`
4. Scopes: Check `project:releases` and `project:write`
5. Copy the token (you won't be able to see it again)

**How to add to GitHub:**
```bash
# Via GitHub UI:
Repository → Settings → Secrets and variables → Actions → New repository secret
Name: SENTRY_AUTH_TOKEN
Value: [paste token]

# Or via gh CLI:
gh secret set SENTRY_AUTH_TOKEN --body "YOUR_TOKEN_HERE"
```

### 2. `SENTRY_ORG`

**What it is:** Your Sentry organization slug (the short name in URLs).

**How to find it:**
- Look at your Sentry URL: `https://sentry.io/organizations/YOUR-ORG-SLUG/`
- Or find it in: Sentry → Settings → Organization Settings → General

**Example value:** `nikhilsh` or `papertrail-team`

**How to add to GitHub:**
```bash
gh secret set SENTRY_ORG --body "your-org-slug"
```

### 3. `SENTRY_PROJECT`

**What it is:** Your Sentry project slug for PaperTrail.

**How to find it:**
- Look at your Sentry URL: `https://sentry.io/organizations/YOUR-ORG/projects/YOUR-PROJECT/`
- Or find it in: Sentry → Projects → [Your Project] → Settings → General

**Example value:** `papertrail-ios` or `papertrail`

**How to add to GitHub:**
```bash
gh secret set SENTRY_PROJECT --body "your-project-slug"
```

## Verification

### 1. Check Workflow Run

After pushing to master or triggering a workflow_dispatch:

1. Go to GitHub Actions → "Build Ad Hoc IPA" workflow
2. Look for the "Upload dSYMs to Sentry" step
3. Should see: `✅ dSYMs uploaded successfully to Sentry`

### 2. Verify in Sentry

1. Go to Sentry → Your Project → Settings → Debug Files
2. You should see uploaded dSYM files with:
   - Architecture (arm64, arm64e)
   - UUID
   - Upload timestamp
3. Check that "Source Context" is available (source files bundled with symbols)

### 3. Test Crash Symbolication

After the next crash report:
1. Go to Sentry → Issues → [Your Issue]
2. Stack trace should now show:
   - Function names (not just hex addresses)
   - File names and line numbers
   - Code snippets from your source (if `--include-sources` worked)

## Troubleshooting

### "No dSYMs directory found"

**Cause:** The archive didn't produce dSYM files.

**Fix:** Verify Xcode build settings:
```bash
# Check current settings:
xcodebuild -project PaperTrail.xcodeproj -scheme PaperTrail -configuration Release -showBuildSettings | grep DEBUG_INFORMATION_FORMAT

# Should output:
DEBUG_INFORMATION_FORMAT = dwarf-with-dsym
```

If it shows `dwarf` instead, update the Release configuration in Xcode:
- Project → Build Settings → Debug Information Format → Release → "DWARF with dSYM File"

### "Authentication failed"

**Cause:** Invalid or missing `SENTRY_AUTH_TOKEN`.

**Fix:**
1. Regenerate the token in Sentry
2. Ensure scopes include `project:write` and `project:releases`
3. Update the GitHub secret

### "Project not found"

**Cause:** Incorrect `SENTRY_ORG` or `SENTRY_PROJECT` values.

**Fix:**
1. Verify the org and project slugs in your Sentry URL
2. Update the GitHub secrets to match exactly

### dSYMs uploaded but crashes still not symbolicated

**Possible causes:**
1. **Build UUID mismatch** - The uploaded dSYMs don't match the crashed build
   - Verify the build was uploaded after the workflow change
   - Check Sentry Debug Files page for the correct UUID
   
2. **Wrong Sentry project** - Check that crashes are going to the same project where dSYMs are uploaded

3. **Bitcode enabled** - Not applicable (ad-hoc builds don't use bitcode)

## Architecture

### dSYM Generation Flow

```
xcodebuild archive
    ↓
PaperTrail.xcarchive/
    ├── Products/
    │   └── Applications/
    │       └── PaperTrail.app
    ├── dSYMs/                    ← Debug symbols generated here
    │   └── PaperTrail.app.dSYM
    └── Info.plist
```

### Upload Flow

```
1. Archive built (dSYMs at $ARCHIVE_PATH/dSYMs/)
2. IPA exported to $EXPORT_PATH
3. sentry-cli installs via curl script
4. sentry-cli debug-files upload:
   - Scans dSYMs directory
   - Extracts source file references
   - Bundles source code (--include-sources)
   - Uploads to Sentry API
5. Sentry indexes symbols by UUID
6. Future crashes auto-symbolicate
```

### Security Notes

- ✅ Uses GitHub Secrets (not hardcoded tokens)
- ✅ Token scoped to specific permissions
- ✅ Source code uploaded to Sentry (needed for Source Context)
  - Only uploaded to your private Sentry project
  - Not publicly accessible
  - Can be disabled by removing `--include-sources` flag

## Alternative Approaches Considered

### 1. Xcode Build Phase Script
**Not used** because:
- Requires sentry-cli installed on CI runner (adds dependency)
- Less flexible than GitHub Actions step
- Harder to debug

### 2. Fastlane Plugin
**Not used** because:
- Project doesn't use Fastlane
- Would require additional setup
- GitHub Actions approach is simpler

### 3. Manual Upload
**Not used** because:
- Not automated
- Error-prone
- Defeats purpose of CI/CD

## References

- [Sentry iOS dSYM Documentation](https://docs.sentry.io/platforms/apple/guides/ios/dsym/)
- [sentry-cli Installation](https://docs.sentry.io/cli/installation/)
- [Sentry Source Context](https://docs.sentry.io/platforms/apple/guides/ios/data-management/debug-files/source-context/)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)

## Quick Reference

**Current Sentry SDK version (in project):** sentry-cocoa (via SPM, upToNextMajor)

**Workflow location:** `.github/workflows/ios-adhoc-ota.yml`

**sentry-cli version:** 2.40.0 (pinned for reproducibility)

**Upload includes:**
- ✅ Debug symbols (dSYMs)
- ✅ Source code (for Source Context)
- ✅ Automatic UUID matching

**Secrets required:**
1. `SENTRY_AUTH_TOKEN` (auth token with project:write scope)
2. `SENTRY_ORG` (your org slug)
3. `SENTRY_PROJECT` (your project slug)

**Already configured (no action needed):**
- ✅ Sentry SDK in app code (`PaperTrailApp.swift`)
- ✅ `SENTRY_DSN` secret (already set)
- ✅ dSYM generation in Xcode (Release builds)
- ✅ Workflow triggers (push to master, manual dispatch)
