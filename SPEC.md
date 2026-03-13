# PaperTrail Spec

## One-line pitch
A SwiftUI app that lets gadget and appliance buyers capture receipts and warranty proof automatically, then find them instantly when they need them.

## Primary target user
People who buy:
- gadgets
- consumer electronics
- appliances
- home devices
- higher-value household items

## Product principles
- capture should feel mostly automatic
- users should not need to manually organize files
- search should be better than Photos
- product records matter more than document records
- data durability is a trust requirement

## Core requirements
### Capture
- photo/document scan flow
- OCR runs automatically
- app suggests metadata
- user can correct quickly

### Retrieval
- search by product name, merchant, date, category, notes, OCR text
- records open into a product-centric detail view

### Durability
- iCloud sync is core
- deleting the app should not mean losing records

## Proposed stack
- SwiftUI
- MVVM
- Combine
- VisionKit + Vision
- Core Data
- NSPersistentCloudKitContainer / CloudKit sync
