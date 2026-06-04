# Sentry dSYM Upload - Quick Start

## What Changed

✅ Modified `.github/workflows/ios-adhoc-ota.yml` to automatically upload dSYMs to Sentry after each build

## Required Secrets (Add These Now)

You need to add **3 secrets** to your GitHub repository settings:

### 1. Create Sentry Auth Token

1. Go to: https://sentry.io/settings/auth-tokens/
2. Click "Create New Token"
3. Name: `GitHub Actions - PaperTrail dSYM Upload`
4. Scopes: ✓ `project:releases` ✓ `project:write`
5. Copy the token

```bash
# Add to GitHub:
gh secret set SENTRY_AUTH_TOKEN --body "sntrys_YOUR_TOKEN_HERE"
```

### 2. Set Organization Slug

Find your org slug from your Sentry URL: `sentry.io/organizations/YOUR-ORG-SLUG/`

```bash
gh secret set SENTRY_ORG --body "your-org-slug"
```

### 3. Set Project Slug

Find your project slug from: `sentry.io/organizations/YOUR-ORG/projects/YOUR-PROJECT/`

```bash
gh secret set SENTRY_PROJECT --body "papertrail-ios"
```

## Verify It's Working

1. Push to master or trigger workflow manually
2. Check GitHub Actions → "Upload dSYMs to Sentry" step
3. Should see: `✅ dSYMs uploaded successfully to Sentry`
4. Verify in Sentry: Settings → Debug Files → see uploaded dSYMs

## What You Get

- ✅ Symbolicated stack traces (function names, not hex addresses)
- ✅ File names and line numbers in crash reports
- ✅ Source code snippets in Sentry (via `--include-sources`)
- ✅ Automatic upload on every CI build
- ✅ No runtime code changes needed

## Troubleshooting

**"Authentication failed"** → Regenerate `SENTRY_AUTH_TOKEN` with correct scopes

**"Project not found"** → Double-check `SENTRY_ORG` and `SENTRY_PROJECT` values

**"No dSYMs directory found"** → Xcode should already be configured correctly (DEBUG_INFORMATION_FORMAT = dwarf-with-dsym for Release)

## Full Documentation

See `SENTRY_DSYM_SETUP.md` for complete details, architecture notes, and troubleshooting.
