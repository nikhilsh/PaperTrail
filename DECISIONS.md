# Decisions

## 2026-03-13

### Name
- Chosen name: **PaperTrail**

### Target user
- Initial focus: gadget and appliance buyers

### Capture philosophy
- Capture should feel mostly automatic

### Durability
- iCloud sync is a core requirement, not a nice-to-have

### Technical direction
- SwiftUI + MVVM + Combine
- VisionKit/Vision for scanning and OCR
- Core Data + CloudKit for persistence and sync

### Repo visibility
- GitHub repo should start private

### V1 modeling choice
- Keep the domain model small: `PurchaseRecord` + `Attachment`
- Avoid a separate `Tag` entity in v1

### V1 navigation choice
- Build around a simple three-tab shell: Library, Capture, Settings

### Build order choice
- Build local-first, but design with CloudKit sync in mind from the start
- Implement sync after local model, persistence, and retrieval flow are stable

### Project bootstrap choice
- Start with a plain SwiftUI app shell and add persistence deliberately
- Avoid over-relying on Xcode-generated Core Data scaffolding

### Product direction shift
- PaperTrail is not just a receipt vault
- It should evolve toward a device registry + warranty/support tool
- Device records are the primary object; receipts and warranty documents are supporting evidence

### Support lookup policy
- If a service/support number is inferred or looked up from external sources rather than extracted from proof, it must be clearly labeled as a best guess / unverified

## 2026-03-20

### iOS 26+ deployment target
- Raised minimum deployment target from iOS 18.0 to iOS 26.0
- Enables use of Apple Foundation Models framework for on-device LLM extraction
- iOS 26 is the current release; no backward-compatibility burden for this early-stage app
- CI already uses Xcode 26.3

### Foundation Models extraction layer
- Added `FoundationModelExtractionService` using Apple's on-device LLM via `@Generable` structured output
- `ReceiptExtractionSchema` defines the JSON schema the model should produce
- Added `ExtractionPipeline` orchestrator that runs FM + heuristic concurrently and merges results
- Heuristic fallback ensures the app works on devices without Apple Intelligence
- Per-field confidence tracking (`ExtractionConfidence`) lets the UI indicate extraction quality
- New fields: `suggestedCategory`, `suggestedWarrantyDurationMonths` flow through from extraction to DraftRecordView
- DraftRecordView shows extraction source badge ("Apple Intelligence" vs "pattern matching")
- `VisionOCRService` simplified to Vision OCR only; field extraction delegated to `ExtractionPipeline`
- Heuristic logic extracted to `HeuristicFieldExtractor` struct (was inline in VisionOCRService)

### Design principle: graceful degradation
- Foundation Models availability is checked at runtime via `LanguageModelSession.isAvailable`
- `#if canImport(FoundationModels)` guards compile-time availability
- App never crashes if the model is unavailable — always falls back to heuristics
