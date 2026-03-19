# PaperTrail Roadmap

## Completed

### Milestone 1 — App Shell (Mar 13)
- SwiftUI tab-based app (Library, Capture, Settings)
- PurchaseRecord model with attachments, support info
- Library with search, summary tiles, record cards
- Capture flow with placeholder scanning + OCR
- Record detail + edit views
- In-memory data store

### Milestone 2 — Core Functionality (Mar 19, commit 4fb387a)
- SwiftData persistence (@Model classes)
- VisionKit document scanner (VNDocumentCameraViewController)
- Real Vision OCR (VNRecognizeTextRequest)
- Image storage on disk (ImageStorageManager)
- PhotosPicker for importing existing images
- Full-screen zoomable image viewer
- Delete record with confirmation
- Full edit view (dates, warranty, attachments)
- Camera usage description

### Milestone 2.5 — Polish & Organization (Mar 19, commit 0194b35)
- Amount/currency fields with OCR price extraction
- Category and tags system
- Local warranty expiry notifications (30d, 7d, day-of)
- Library sort (newest, oldest, name, warranty)
- Library filter (all, active, expiring soon, expired)
- Search includes OCR text + tags
- Context menu delete in library
- Warranty status badges (green/orange/red)
- Smarter OCR: SG date formats, currency detection

### Milestone 3 — Cloud & Identity (Mar 19, commits 256f16b, 1280af7)
- CloudKit sync (SwiftData + automatic iCloud)
- Image data synced via @Attribute(.externalStorage)
- Sign in with Apple (AuthenticationManager)
- Record export as .papertrail shareable packages
- Share sheet integration (AirDrop, Messages, etc.)
- iCloud + Sign in with Apple entitlements

---

## In Progress

### CI/CD Pipeline
- **Status**: Blocked on signing cert
- **Blocker**: Uploaded .p12 is Apple Development cert, need Apple Distribution
- **Team ID mismatch**: Profile uses EHW7L3679R, workflow uses 635A559UST
- **Action needed**: Nik exports correct Apple Distribution .p12 from Keychain Access
- **Once unblocked**: Update GitHub secret, change workflow TEAM_ID, verify pipeline

---

## Planned — Near Term

### Milestone 4 — Multi-User Sharing (High Priority)
**Approach: Hybrid Core Data + SwiftData**

The research concluded that CloudKit sharing via `NSPersistentCloudKitContainer` is the only serverless way to get real multi-user shared records on iOS. SwiftData doesn't support `CKShare` natively.

**Architecture:**
- Keep SwiftData for private records, drafts, settings
- Add Core Data + NSPersistentCloudKitContainer for shared records
- Shared records live in a separate CloudKit shared zone
- UICloudSharingController for invite/manage participants (wrapped in UIViewControllerRepresentable)

**Implementation plan:**
1. Define Core Data model (.xcdatamodeld) mirroring PurchaseRecord + Attachment
2. Set up NSPersistentCloudKitContainer with private + shared store configs
3. Build CoreDataSharingManager to handle share creation, acceptance, participant management
4. CloudSharingView wrapping UICloudSharingController
5. Handle share acceptance via scene delegate / universal links
6. UI to distinguish "My Records" vs "Shared With Me"
7. Conflict resolution strategy for concurrent edits
8. Migrate existing export-based sharing to coexist with live sharing

**Complexity:** 10-20 days for production quality
**Risk:** Two persistence systems add maintenance overhead
**Prerequisite:** Sign in with Apple (done), iCloud entitlements (done)

### iCloud Sync Status UI
- Add a `CloudSyncMonitor` for PaperTrail so users can see when records are uploading/downloading with iCloud
- SwiftData does not expose sync progress directly, but `NSPersistentCloudKitContainer.eventChangedNotification` can be observed from the underlying Core Data / CloudKit stack
- Planned states:
  - idle
  - syncing("Uploading to iCloud")
  - syncing("Downloading from iCloud")
  - success
  - failed(error)
- Surface this as a small status pill/banner in Settings and optionally after save/import actions
- Nice follow-up: keep last sync timestamp + last error for debugging user reports
- Reference: AzamSharp article on SwiftData iCloud sync status (2026-03-16)
- Complexity: 1-2 days

### Spotlight Search Integration
- Index records via CSSearchableItem
- Search PaperTrail records from iOS home screen
- Low complexity (1-2 days), high discoverability impact

### Haptic Feedback
- On save, delete, scan complete
- Tiny effort, noticeable polish

---

## Planned — Medium Term

### Share Extension
- Accept images/PDFs from other apps into PaperTrail
- Key for daily workflow: screenshot receipt in WhatsApp → share to PaperTrail
- Requires App Group for shared container access
- Complexity: 3-5 days

### Onboarding Flow
- First-launch walkthrough: scan → OCR → save
- Explain value proposition visually
- Complexity: 2-3 days

### Widget
- Home screen widget showing expiring warranties
- WidgetKit + App Intent
- Complexity: 2-3 days

### PDF Export
- Generate PDF of a record with attachments
- Useful for insurance claims, returns
- Complexity: 1-2 days

---

## Planned — Longer Term

### Biometric Lock
- Face ID / Touch ID to protect records
- LAContext authentication
- Complexity: 1-2 days

### App Icon
- Custom designed icon
- Replace default Xcode icon

### Receipt Amount Breakdown
- Subtotal, tax, total as separate fields
- Enhanced OCR to extract line items

### Merchant Auto-Complete
- Suggest previously used merchant names
- Local dictionary from existing records

### Accessibility Audit
- VoiceOver labels on all custom views
- Dynamic Type testing
- Reduce motion support

### Multiple Scan Sessions
- Add more pages/photos to an existing record
- Currently only at creation time

### Dark Mode Audit
- Verify all custom colors work in both modes
- Test on OLED vs LCD displays

---

## Architecture Notes

### Current Stack
- SwiftUI (iOS 18+)
- SwiftData for persistence
- CloudKit automatic sync (private)
- Vision framework for OCR
- VisionKit for document scanning
- AuthenticationServices (Sign in with Apple)
- UserNotifications (warranty reminders)

### Future Stack Additions (for sharing)
- Core Data + NSPersistentCloudKitContainer (shared records only)
- CloudKit framework (CKShare, CKContainer)

### Named Agent Setup (OpenClaw)
- **main** (Codex 5.4) — orchestrator, user-facing
- **coder** (Opus 4.6) — code writing, complex Swift
- **ci-worker** (Sonnet 4.5) — GitHub Actions, CI/CD
- **researcher** (Codex 5.4) — web research, planning

### Key Identifiers
- Bundle ID: nikhilsh.PaperTrail
- iCloud container: iCloud.nikhilsh.PaperTrail
- Team ID (profile): EHW7L3679R
- Team ID (project): 635A559UST (needs alignment)
- Repo: github.com:nikhilsh/PaperTrail
- Branch: master
