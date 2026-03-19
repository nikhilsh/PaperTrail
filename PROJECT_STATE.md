# PaperTrail — Project State Snapshot
> Last updated: 2026-03-19

## What is it
iOS app (SwiftUI, iOS 18+) for tracking purchase records, receipts, warranties. Scan → OCR → save → search → get reminded before warranty expires.

## Current state: Milestone 3 complete
- SwiftData persistence + CloudKit sync
- VisionKit document scanner + real Vision OCR
- Sign in with Apple
- Record sharing via .papertrail export packages
- Amount/currency, tags, categories
- Warranty expiry notifications
- Library with sort/filter/search (including OCR text)
- Full-screen image viewer, delete, full edit

## Latest commit
- `ab620f9` on `master` — "Add project roadmap with future plans and architecture notes"

## CI/CD status: BLOCKED
- GitHub Actions workflow exists at `.github/workflows/ios-adhoc-ota.yml`
- Fails at Archive step — wrong signing cert
- **Root cause**: Uploaded .p12 is `Apple Development: Nikhil Sharma (635A559UST)`, need `Apple Distribution: Nikhil Sharma (EHW7L3679R)`
- **Team ID mismatch**: Profile uses `EHW7L3679R`, workflow/project uses `635A559UST`
- **To fix**: Nik exports correct Apple Distribution .p12, I update GitHub secret + workflow TEAM_ID

## Key identifiers
- Repo: `github.com:nikhilsh/PaperTrail` branch `master`
- Bundle ID: `nikhilsh.PaperTrail`
- iCloud container: `iCloud.nikhilsh.PaperTrail`
- Team ID (profile/correct): `EHW7L3679R`
- Team ID (project/wrong): `635A559UST`
- Profile UUID: `cb463b60-7799-4f63-bb85-3d3ae21971a0`
- Project path: `/root/.openclaw/workspace/projects/papertrail`
- Workflow file: `.github/workflows/ios-adhoc-ota.yml`

## Next steps
See ROADMAP.md for full plan. Priority order:
1. Fix CI (needs correct .p12 from Nik)
2. Spotlight search indexing
3. Share extension
4. Multi-user sharing (hybrid Core Data + SwiftData — researched, planned)

## File inventory (Swift source)
PaperTrailApp.swift, AppShellView.swift, LibraryView.swift, CaptureView.swift,
DraftRecordView.swift, RecordDetailView.swift, EditRecordView.swift, SettingsView.swift,
ImageViewerView.swift, ShareSheetView.swift, DocumentScannerView.swift,
PurchaseRecord.swift, Attachment.swift, SupportInfo.swift, OCRExtractionResult.swift,
OCRService.swift, ScanningService.swift, ImageStorageManager.swift,
NotificationManager.swift, AuthenticationManager.swift, RecordSharingManager.swift,
ContentView.swift (legacy stub), PurchaseRecordStore.swift (deprecated stub),
PurchaseRecordRepository.swift (deprecated stub)
