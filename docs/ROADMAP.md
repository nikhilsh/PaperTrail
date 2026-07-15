# PaperTrail Roadmap

Updated 2026-07-15. The app is **live on the App Store** (v1.0, build 22, READY_FOR_SALE
since 2026-07-08) as "PaperTrail — Proof of Purchase". OTA/TestFlight channels run ahead
of the store build. Monetization strategy: [`docs/MONETIZATION.md`](MONETIZATION.md).

## North star

Build a product users trust immaculately: no bugs, no dark patterns, no lock-in.
Every wave ships through PR → CI → adversarial review → device verification before the
flag flips or the store update goes out. Trust features (export, privacy, transparency)
are never paywalled.

---

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
- Library sort/filter, search incl. OCR text + tags
- Warranty status badges; SG date/currency OCR smarts

### Milestone 3 — Cloud & Identity (Mar 19, commits 256f16b, 1280af7)
- CloudKit sync (SwiftData + automatic iCloud)
- Disk-based image storage synced as CKAssets (CloudImageSyncManager)
- Record export as .papertrail shareable packages, share sheet integration

### The Archive redesign + AI extraction overhaul (Jun–Jul)
- Full visual/IA reskin (warm-dark, paper-archival identity)
- Foundation Models on-device extraction + heuristic fallback, structured OCR
- Community learning pipeline (Supabase, opt-in), correction logging
- Sentry observability with dSYM upload in CI

### App Store wave (Jul 8, builds 22–23, PRs #60–#64)
- Return-window tracking, App Intents/Siri/Shortcuts, serial barcode scanning
- Compliance: PrivacyInfo.xcprivacy, consent-gated community learning, privacy site
- CI/CD complete: ad-hoc OTA (rolling `adhoc-latest` → papertrail.kaopeh.com),
  TestFlight lane, website deploy, CloudKit schema workflow. Team ID unified (EHW7L3679R).
- **v1.0 (build 22) shipped to the App Store**

### Milestone 4 — Household sharing (Jul 13–15, PRs #67–#78, builds 24–31)
- **Architecture: zone-wide CKShare + dual CKSyncEngine beside SwiftData** — the
  roadmap's earlier hybrid Core Data plan was researched and REJECTED (CD_* record-type
  collision risk with the load-bearing store). Design of record:
  [`docs/SHARING_ARCHITECTURE.md`](SHARING_ARCHITECTURE.md).
- Shared-in records live in HouseholdCache (JSON), never the SwiftData store
- CKAsset image sync, read-only member views, "Shared with me" Library section
- Push (aps-environment + remote-notification background mode), CloudKit schema
  deployed to production, share-invite branding, member-perspective UI
- Adversarially reviewed (3-lens panel, 12 fixes) + two-device verified
- Store build is still flag-off; flag-on store update ships after Wave 1

---

## In Progress — Wave 1: "The day it breaks" (Jul 15)

All in-app, no new targets, no schema changes. One OTA build once green.

- **Deep-link spine** (`papertrail://`), notification tap-through (taps land on the
  record, not the app), Home Screen quick actions, OpenRecordIntent routing
- **Spotlight indexing** — records + receipt OCR text searchable from iOS search
- **Search fix** — serialNumber + room included in in-app search (bug-grade gap)
- **Support-contact suggestions** — wire the dead Settings toggle to a curated
  on-device brand→support directory (estimated-confidence, "verify before calling")
- **Review prompting** — StoreKit requestReview at delight moments, once per version
- **Mail/Files import** — CFBundleDocumentTypes: open PDFs/images from Mail, Files,
  Safari straight into the import pipeline (80% of a share extension at 10% cost)

Also shipping: Rate link fix + Settings/Diagnostics cleanup (PR #79), member Library
empty-state fix (PR #78).

## Next — Wave 2: "Money saved"

- **Monthly Warranty Digest** — one notification/panel: expiring coverage total,
  closing return windows, "check it for defects while repairs are free" nudges
- **Insurance-Ready Report** — one-tap PDF: everything by room with photos, serials,
  receipts, honest depreciation-based estimates; household-wide; doubles as the
  anti-lock-in export guarantee and the moving-house inventory pack
- **Proof Score** — per-record completeness (receipt? serial? warranty? photo?) and a
  "worst offenders" fix-it list; feeds digest nudges

## Then — Wave 3: extensions (infra-heavy)

New targets = pbxproj surgery + App Group + new provisioning + CI signing changes,
done blind (no local Xcode). Ship infra first as its own empty-but-compiling PR.

- **Widget extension** — Home/Lock Screen "expiring soon" widgets + Control Center
  scan button. Widgets read a JSON snapshot in the App Group, NEVER the SwiftData
  store (moving the CloudKit-backed store is a forbidden-risk migration)
- **Share extension** — screenshots/images/PDFs shared from any app land in an App
  Group inbox; main app drains it into the import pipeline (no OCR in-extension)

## Planned — Later

- **Monetization v1** — StoreKit 2 subscription ("PaperTrail Plus"): household
  sharing beyond 1 member, insurance report, advanced reminders. Scanning and export
  stay free forever. Details: [`docs/MONETIZATION.md`](MONETIZATION.md)
- **Warranty Brain** (big bet, deferred — hard): auto coverage stack — manufacturer
  warranty length by brand, AppleCare detection, credit-card warranty extension,
  split parts/labor warranties. Most-wished least-solved gap in the category
- **Recall alerts** — local matching of owned items against public recall feeds
  (CPSC/FDA); Centriq's orphaned killer feature; retention driver
- **Visual intelligence / IndexedEntity** (iOS 26) — point the camera at the broken
  appliance, PaperTrail surfaces the record; interactive Siri snippets
- **"Year in Stuff"** — annual shareable wrapped, FM-written narrative, on-device
- **Ask Your Archive** — FM Q&A over records ("which Samsung stuff is still covered?")
- **Spending insights** — Swift Charts by room/category/merchant (per-currency)
- Onboarding flow; iCloud sync status pill; biometric lock; accessibility audit;
  merchant auto-complete; multiple scan sessions; receipt amount breakdown

---

## Architecture Notes

### Current stack
- SwiftUI (iOS 26+), SwiftData + CloudKit automatic sync (private store)
- CKSyncEngine ×2 (private + shared DB) for household sharing, beside SwiftData
- Vision/VisionKit OCR + scanning; Foundation Models extraction w/ heuristic fallback
- UserNotifications; App Intents; Sentry (events, breadcrumbs, structured logs)
- CI: GitHub Actions (sim tests on PR; ad-hoc OTA on master push; TestFlight,
  website, CloudKit schema on dispatch). No local Xcode — CI green = compiles only;
  UI/runtime claims need on-device verification.

### Key identifiers
- Bundle ID: nikhilsh.PaperTrail · iCloud container: iCloud.nikhilsh.PaperTrail
- Team ID: EHW7L3679R (unified — the old 635A559UST mismatch is resolved)
- App Store: app id 6788663812 · Repo: github.com/nikhilsh/PaperTrail (master)
