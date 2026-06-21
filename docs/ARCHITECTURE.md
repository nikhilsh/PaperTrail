# Architecture

## Stack
- UI: SwiftUI (iOS 26+)
- Presentation: MVVM
- Reactive/event layer: Combine
- OCR/scanning: VisionKit + Vision
- Field extraction: Apple Foundation Models (on-device LLM) with heuristic fallback
- Persistence: SwiftData
- Sync: CloudKit-backed SwiftData

## Layering
### Presentation
- SwiftUI views
- view models transform state + user intents

### Domain
- record creation/editing logic
- search/filter use cases
- warranty date derivation helpers

### Data
- repositories
- Core Data entities
- mappers between persistence and domain models
- sync configuration

### Services
- scan service (VisionKit document camera)
- OCR service (Vision text recognition)
- extraction pipeline (Foundation Models → heuristic fallback)
- attachment storage service
- cloud image sync service

## Principles
- keep business logic out of views
- isolate OCR from UI
- extraction is protocol-based and pluggable (Foundation Models, heuristic, or future services)
- use protocols around repositories/services where helpful
- avoid leaking persistence types everywhere
- design for CloudKit from day one, even if local-first initially
- graceful degradation: features requiring Apple Intelligence degrade to heuristics, never crash

## Extraction pipeline

```text
UIImage → VisionOCR (raw text) → ExtractionPipeline
                                     ├── FoundationModelExtractionService (primary, if available)
                                     └── HeuristicExtractionService (fallback, always runs)
                                     → merge → StructuredExtractionResult → OCRExtractionResult
```

The pipeline runs both services concurrently and merges results. Foundation Model values
take priority; heuristic values fill any gaps. The merged result is bridged to
`OCRExtractionResult` for backward compatibility with existing views.

## Initial folder direction
```text
PaperTrail/
  App/
  Core/
  Features/
    Library/
    Capture/
    RecordDetail/
    EditRecord/
    Settings/
  Services/
  Data/
  Resources/
```
