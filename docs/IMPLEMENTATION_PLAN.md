# Implementation Plan

## Objective
Build a disciplined v1 of PaperTrail without trying to ship scanning, OCR, search, and sync all at once.

## Strategy
Build in layers:
1. app shell + local model
2. basic persistence and record flows
3. capture + OCR
4. retrieval/search quality
5. iCloud durability

This is the least glamorous path, which usually means it is the correct one.

## Phase 1 — App shell and local structure
Deliverables:
- Xcode project/app target exists
- folder/group structure matches the architecture direction
- root navigation shell exists
- placeholder screens exist for Library, Capture, Detail, Edit, Settings
- domain models created in code
- repository and service protocols defined

Output:
A compilable app skeleton with clear structure.

## Phase 2 — Local persistence
Deliverables:
- Core Data stack set up
- `PurchaseRecordEntity` and `AttachmentEntity`
- mapping layer between entities and domain models
- create/read/update basic flows working
- manual add/edit flow functioning without OCR yet

Output:
The app can store and display purchase records locally.

## Phase 3 — Capture and OCR
Deliverables:
- VisionKit or camera capture flow integrated
- attachment file storage on disk
- OCR service using Vision
- extracted text saved with attachments
- draft record creation from OCR output
- edit/review UX after capture

Output:
Users can scan something and get a useful draft record.

## Phase 4 — Search and retrieval
Deliverables:
- library search over product, merchant, notes, category, OCR text
- sort/filter behavior
- detail screen polish
- list item summaries that make retrieval fast

Output:
The app becomes genuinely useful beyond being a receipt bucket.

## Phase 5 — iCloud durability
Deliverables:
- CloudKit-backed Core Data sync
- sync-safe persistence assumptions validated
- settings/status surfaces for sync state
- reinstall/device-change test checklist

Output:
User trust improves because data survives deletion/device changes.

## Suggested coding order
### First code artifacts
- `PurchaseRecord` model
- `Attachment` model
- repository protocols
- app root and `LibraryView`
- mock repository for UI iteration

### Then
- persistence layer
- edit/detail flow
- capture flow
- OCR integration
- sync integration

## Testing priorities
- mapping correctness between Core Data and domain models
- record create/edit flows
- OCR extraction edge cases
- search retrieval behavior
- CloudKit sync sanity on multiple devices later

## Things to avoid early
- overbuilding reminder logic
- perfect extraction heuristics too soon
- multiple storage abstractions for no reason
- adding too many filters/tags before retrieval proves weak
- forcing SwiftData just because it is newer

## Definition of Milestone 1 done
Milestone 1 is done when:
- the app builds
- the structure is clean
- placeholder screens exist
- domain models exist
- protocols for repositories/services exist
- there is a clear path to swapping mock data for local persistence
