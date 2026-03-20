#!/bin/bash
# Verify dSYM configuration for PaperTrail
# Run this locally before pushing to CI

set -e

PROJECT_PATH="PaperTrail.xcodeproj"
SCHEME="PaperTrail"
CONFIGURATION="Release"

echo "🔍 Verifying dSYM configuration for PaperTrail..."
echo ""

# Check Xcode build settings
echo "1️⃣ Checking Xcode DEBUG_INFORMATION_FORMAT setting..."
DEBUG_FORMAT=$(xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null | grep "DEBUG_INFORMATION_FORMAT =" | head -1 | awk '{print $3}')

if [ "$DEBUG_FORMAT" = "dwarf-with-dsym" ]; then
    echo "   ✅ DEBUG_INFORMATION_FORMAT = dwarf-with-dsym (correct)"
else
    echo "   ❌ DEBUG_INFORMATION_FORMAT = $DEBUG_FORMAT (should be dwarf-with-dsym)"
    echo "   Fix: Xcode → Project Settings → Build Settings → Debug Information Format → Release → 'DWARF with dSYM File'"
    exit 1
fi

echo ""

# Check if sentry-cocoa is in dependencies
echo "2️⃣ Checking Sentry SDK integration..."
if grep -q "sentry-cocoa" "$PROJECT_PATH/project.pbxproj"; then
    echo "   ✅ sentry-cocoa package reference found"
else
    echo "   ⚠️  Warning: sentry-cocoa not found in project.pbxproj"
fi

echo ""

# Check GitHub secrets (can't read values, but can check if gh is configured)
echo "3️⃣ Checking GitHub CLI access..."
if command -v gh &> /dev/null; then
    if gh auth status &> /dev/null; then
        echo "   ✅ GitHub CLI authenticated"
        echo ""
        echo "   📋 Required GitHub Secrets (cannot verify values remotely):"
        echo "      - SENTRY_AUTH_TOKEN (Sentry auth token with project:write scope)"
        echo "      - SENTRY_ORG (your Sentry org slug)"
        echo "      - SENTRY_PROJECT (your Sentry project slug)"
        echo "      - SENTRY_DSN (already configured)"
        echo ""
        echo "   Run 'gh secret list' to see which secrets are set"
    else
        echo "   ⚠️  GitHub CLI not authenticated. Run 'gh auth login' to check secrets"
    fi
else
    echo "   ⚠️  GitHub CLI (gh) not installed. Cannot check secrets"
fi

echo ""
echo "4️⃣ Checking workflow file..."
WORKFLOW_FILE=".github/workflows/ios-adhoc-ota.yml"
if [ -f "$WORKFLOW_FILE" ]; then
    if grep -q "sentry-cli debug-files upload" "$WORKFLOW_FILE"; then
        echo "   ✅ Workflow contains Sentry dSYM upload step"
    else
        echo "   ❌ Workflow missing Sentry dSYM upload step"
        exit 1
    fi
    
    if grep -q "SENTRY_AUTH_TOKEN" "$WORKFLOW_FILE"; then
        echo "   ✅ Workflow references SENTRY_AUTH_TOKEN secret"
    else
        echo "   ❌ Workflow missing SENTRY_AUTH_TOKEN reference"
        exit 1
    fi
else
    echo "   ❌ Workflow file not found: $WORKFLOW_FILE"
    exit 1
fi

echo ""
echo "✅ All checks passed! dSYM upload configuration looks good."
echo ""
echo "Next steps:"
echo "1. Ensure GitHub secrets are set (SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT)"
echo "2. Push to master or trigger workflow_dispatch"
echo "3. Check GitHub Actions logs for 'Upload dSYMs to Sentry' step"
echo "4. Verify in Sentry: Settings → Debug Files"
