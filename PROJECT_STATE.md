# PaperTrail — Project State Snapshot
> Last updated: 2026-03-20

## What it is
iOS app (SwiftUI, iOS 18+) for tracking purchase records, receipts, warranties. Scan → OCR → save → search → get reminded before warranty expires.

## Current state: Milestone 3 working with OTA + CloudKit + Image Sync
- SwiftData persistence
- CloudKit sync **working in OTA build**
- **CloudKit CKAsset image sync** — proof images sync across devices via separate CKRecord type
- VisionKit document scanner + real Vision OCR
- Sign in with Apple
- Record sharing via `.papertrail` export packages
- Amount/currency, tags, categories
- Warranty expiry notifications
- Library with sort/filter/search (including OCR text)
- Full-screen image viewer, delete, full edit
- OTA install page on GitHub Pages
- Sentry runtime enabled in OTA builds
- Sentry dSYM upload wired in CI

## Latest verified runtime status
From Nik's successful test build:
- Backend: `CloudKit`
- Status: `Active`
- Sentry: `Enabled`
- CK account: `Available`
- Preflight: `User record lookup succeeded`
- Container: `iCloud.nikhilsh.PaperTrail`

## Image Sync Architecture
Proof images are synced across devices using a **separate CloudKit CKAsset strategy** that runs alongside (not inside) the SwiftData/CloudKit mirror:

### How it works
1. **SwiftData syncs metadata**: `Attachment` model (id, recordID, localFilename, type, ocrText) syncs via the existing CloudKit-backed SwiftData store
2. **CKAsset syncs binary data**: A dedicated `ImageAsset` record type in the same CloudKit container stores the actual JPEG image data as a `CKAsset`
3. **Deterministic record names**: Each image's CloudKit record name is `img-<attachmentUUID>`, so both devices can independently resolve the same record
4. **Bidirectional sync on launch**: App uploads local images missing from CloudKit, then downloads CloudKit images missing locally
5. **On-demand download**: When viewing a record, missing images are automatically fetched; tapping a missing thumbnail triggers immediate download
6. **CloudImageStatusOverlay**: Visual indicators on thumbnails show sync state (downloading, missing, error)

### Key files
- `CloudImageSyncManager.swift` — singleton managing upload/download/delete of CKAsset images
- `CloudImageStatusView.swift` — SwiftUI overlay component for sync status badges
- Changes wired into: `PaperTrailApp`, `DraftRecordView`, `RecordDetailView`, `LibraryView`, `SettingsView`, `ImageViewerView`

### Design constraints respected
- **No SwiftData model changes** — `Attachment` schema unchanged, no risk of CloudKit migration issues
- **No image blobs in SwiftData** — images stay out of the synced store
- **Same CloudKit container** — uses `iCloud.nikhilsh.PaperTrail` private database
- **Graceful degradation** — if CloudKit image fetch fails, app shows placeholder with retry option

## What fixed CloudKit
The core issue was SwiftData container/schema architecture, not provisioning or CloudKit account access.

Working architecture now:
- single CloudKit-backed SwiftData store
- no persisted SwiftData `@Relationship` between `PurchaseRecord` and `Attachment`
- `Attachment` linked via `recordID`
- image blobs stored on disk via `ImageStorageManager`, not inside synced SwiftData model
- macro-safe stored-property defaults for SwiftData models

## CI/CD status: HEALTHY
- Workflow: `.github/workflows/ios-adhoc-ota.yml`
- OTA / Pages / rolling release working
- Latest key successful runs:
  - `23326327732` — success — macro-safe SwiftData model defaults
  - `23326513665` — success — OTA page polish + local-time display + confirmed dSYM upload
- Verified CI log shows dSYM upload succeeded to Sentry.

## Observability
- Runtime config is injected through generated `PaperTrail/GeneratedSecrets.swift` during CI builds.
- GitHub secrets now include:
  - `SENTRY_DSN`
  - `SENTRY_AUTH_TOKEN`
  - `SENTRY_ORG`
  - `SENTRY_PROJECT`
- Note: `SENTRY_PROJECT` is currently set to a numeric value; if future Sentry CLI steps fail, verify whether Sentry expects the project slug instead.

## Key identifiers
- Repo: `github.com:nikhilsh/PaperTrail` branch `master`
- Project path: `/root/.openclaw/workspace/projects/papertrail`
- Bundle ID: `nikhilsh.PaperTrail`
- iCloud container: `iCloud.nikhilsh.PaperTrail`
- Team ID: `EHW7L3679R`
- OTA page: `https://nikhil.sh/PaperTrail/`
- Rolling release tag: `adhoc-latest`

## Notable recent commits
- `99c90c4` — Use macro-safe SwiftData model defaults
- `16bbcf5` — Polish OTA page and show local upload time
- `53745a3` — single-store SwiftData / CloudKit direction (app-side fix lane)

## Known follow-ups
1. Verify one manual Sentry test event appears symbolicated in Sentry UI.
2. Improve Apple account display/name persistence UX.
3. Consider cleanup/squash of the messy debugging commit history **only if Nik explicitly approves a force-push/history rewrite**.
4. **CloudKit ImageAsset record type**: The `ImageAsset` record type will be auto-created in CloudKit on first upload. Verify it appears in the CloudKit Dashboard after the first OTA test.
5. Consider adding CKSubscription for push-based image arrival notification (currently uses poll-on-launch + on-demand).
6. Test image sync end-to-end between two devices on the same iCloud account.
