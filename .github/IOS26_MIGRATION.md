# iOS 26+ Migration Checklist

This document tracks the transition from iOS 18.0 to iOS 26+ as the minimum deployment target.

## Status: In Progress

### Completed
- ✅ CI uses Xcode 26.3 on macOS 15 runner (already compatible)
- ✅ Removed hardcoded `IPHONEOS_DEPLOYMENT_TARGET=18.0` override from CI workflow
  - CI now respects whatever deployment target is set in the Xcode project
  - This allows app-side changes to automatically propagate to CI builds

### Pending (App-Side)
- ⏳ Update `PaperTrail.xcodeproj/project.pbxproj` deployment target from 18.0 → 26.0
  - Affects Debug and Release configurations
  - Also update test target configurations
- ⏳ Update documentation references:
  - `ROADMAP.md`: "iOS 18+" → "iOS 26+"
  - `PROJECT_STATE.md`: "iOS 18+" → "iOS 26+"

### OTA Distribution Compatibility
✅ **No changes needed** - The OTA workflow is deployment-target agnostic:
- Manifest templates use environment variables (no hardcoded iOS versions)
- GitHub Pages delivery works for any iOS version
- Ad Hoc provisioning profile controls device compatibility (UDID-based, not iOS version)

### Build Environment
✅ **Already aligned:**
- Xcode 26.3 supports building for iOS 26+ deployment targets
- macOS 15 runner has required SDKs
- Sentry dSYM upload works regardless of deployment target

## Notes
- The CI workflow no longer overrides the deployment target, so project changes automatically flow through
- Once the Xcode project is updated to iOS 26, the next CI run will build with that target
- No breaking changes to the OTA install flow
- Provisioning profile validity is independent of deployment target

## Next Action
Update the Xcode project file deployment target when ready to require iOS 26+.
