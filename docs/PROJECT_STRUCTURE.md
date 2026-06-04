# Project Structure

## Goal
Keep the codebase understandable as the app grows.

## Recommended top-level structure
```text
PaperTrail/
  App/
  Core/
    Models/
    Types/
    Extensions/
    Utilities/
  Features/
    Library/
    Capture/
    RecordDetail/
    EditRecord/
    Settings/
  Data/
    Persistence/
    Repositories/
    Entities/
    Mappers/
  Services/
    OCR/
    Scanning/
    Storage/
  Resources/
```

## Folder responsibilities

### App/
App entry and app-wide composition.

Suggested contents:
- `PaperTrailApp.swift`
- root container/navigation setup
- dependency bootstrap later

### Core/
Shared types that are not feature-specific.

Suggested contents:
- domain models
- shared enums
- common helpers/extensions
- small reusable utilities

### Features/
Feature-by-feature vertical slices.

Suggested subfolders:
- `Library/`
- `Capture/`
- `RecordDetail/`
- `EditRecord/`
- `Settings/`

Within each feature, use a predictable pattern when useful:
- `Views/`
- `ViewModels/`
- `Components/`

### Data/
Persistence and repository concerns.

Suggested contents:
- Core Data stack
- entity definitions / generated classes if used
- repository implementations
- mappers between persistence and domain models

### Services/
Non-persistence operational logic.

Suggested contents:
- OCR service
- document scanning adapter
- file/attachment storage service
- parsing helpers

### Resources/
Assets, strings, static resources as needed.

## Naming guidance
- prefer explicit names over clever names
- suffix view models with `ViewModel`
- suffix repository protocols/implementations clearly
- keep model names aligned with the domain docs

## Structural rule of thumb
If a file only exists to serve one feature, keep it inside that feature.
If it supports the whole app, move it to Core, Data, or Services.
