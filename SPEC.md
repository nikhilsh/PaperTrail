# PaperTrail Spec

## One-line pitch
A SwiftUI app that helps people keep track of the devices they own, the proof of purchase behind them, their warranty status, and how to get support when something breaks.

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
- device records matter more than document records
- data durability is a trust requirement
- warranty/support context should be visible at a glance

## Product direction
PaperTrail started as a receipt and warranty storage idea.
The stronger version of the product is:
- **device ownership registry**
- **warranty memory system**
- **support fallback tool when something breaks**

That means each saved item should feel like a device record first, with receipts and warranty documents attached to it.

## Core requirements
### Capture
- photo/document scan flow
- OCR runs automatically
- app suggests metadata
- user can correct quickly

### Retrieval
- search by product name, merchant, date, category, notes, OCR text
- records open into a product/device-centric detail view

### Durability
- iCloud sync is core
- deleting the app should not mean losing records

### Warranty/support utility
- show warranty status clearly
- attach purchase proof and warranty proof to a device record
- support service/contact details should be available on the record when known
- if support contact is looked up rather than extracted from proof, it must be marked as a best guess / unverified

## Important use cases
### 1. Warranty check
- user opens a device and sees whether it is likely still under warranty
- show purchase date, expiry date, and supporting attachments

### 2. Broken appliance flow
- user taps a device like "Fridge"
- sees warranty status, proof of purchase, and support/service contact path

### 3. Household inventory
- user can browse the important devices they own
- records should feel like owned products, not generic files

### 4. Support lookup
- app may eventually suggest manufacturer/service numbers
- any looked-up contact info must be clearly marked as estimated/best-guess unless verified from user-provided proof

## Proposed stack
- SwiftUI
- MVVM-ish state flow, but prefer SwiftUI-native patterns where possible
- Combine where genuinely useful
- VisionKit + Vision
- Core Data
- NSPersistentCloudKitContainer / CloudKit sync
