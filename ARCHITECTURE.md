# Architecture

## Stack
- UI: SwiftUI
- Presentation: MVVM
- Reactive/event layer: Combine
- OCR/scanning: VisionKit + Vision
- Persistence: Core Data
- Sync: CloudKit-backed Core Data

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
- scan service
- OCR service
- attachment storage service
- parsing helpers

## Principles
- keep business logic out of views
- isolate OCR from UI
- use protocols around repositories/services where helpful
- avoid leaking Core Data types everywhere
- design for CloudKit from day one, even if local-first initially

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
