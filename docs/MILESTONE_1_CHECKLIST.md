# Milestone 1 Checklist

## Objective
Get PaperTrail to a clean, compilable local skeleton with a structure that supports the real app.

## Milestone 1 done means
- [ ] Xcode project exists locally
- [ ] App launches successfully
- [ ] Root navigation shell exists
- [ ] Placeholder `LibraryView` exists
- [ ] Placeholder `CaptureView` exists
- [ ] Placeholder `RecordDetailView` exists
- [ ] Placeholder `EditRecordView` exists
- [ ] Placeholder `SettingsView` exists
- [ ] Initial domain models exist in code
- [ ] Repository protocols exist
- [ ] OCR / scanning service protocols exist
- [ ] Folder/group structure matches project docs
- [ ] App compiles without architectural chaos

## Suggested first file set
- `App/PaperTrailApp.swift`
- `Features/Library/Views/LibraryView.swift`
- `Features/Capture/Views/CaptureView.swift`
- `Features/RecordDetail/Views/RecordDetailView.swift`
- `Features/EditRecord/Views/EditRecordView.swift`
- `Features/Settings/Views/SettingsView.swift`
- `Core/Models/PurchaseRecord.swift`
- `Core/Models/Attachment.swift`
- `Data/Repositories/PurchaseRecordRepository.swift`
- `Services/OCR/OCRService.swift`
- `Services/Scanning/ScanningService.swift`

## What not to do yet
- do not add CloudKit implementation details yet
- do not obsess over reminder logic yet
- do not overbuild tags/categories yet
- do not fight OCR heuristics before the basic flow exists

## Exit criteria
Milestone 1 is complete when the project is pleasant to extend, not when it already feels feature-complete.
