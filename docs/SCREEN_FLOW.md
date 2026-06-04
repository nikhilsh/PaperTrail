# Screen Flow

## V1 philosophy
Keep the app focused on the core loop:
1. capture proof quickly
2. confirm/fix important fields
3. retrieve later with confidence

## Primary screens

### 1. LibraryView
Main entry point.

Responsibilities:
- show all purchase records
- support text search
- show empty state
- provide add button

Key UI elements:
- search bar
- list of records
- floating add button or top-right add action

Tapping a record opens `RecordDetailView`.

### 2. CaptureView
Opened from add flow.

Responsibilities:
- launch camera/document scan
- show processing state while OCR runs
- produce draft extracted fields

States:
- ready to capture
- capturing/scanning
- processing OCR
- extraction complete
- failed/retry

### 3. EditRecordView
User reviews and corrects extracted data.

Responsibilities:
- edit product name
- edit merchant
- edit purchase date
- edit warranty expiry/duration
- edit category/notes
- review attachment type
- save record

This view matters a lot because OCR will never be perfect.

### 4. RecordDetailView
Displays a saved record.

Responsibilities:
- show product metadata clearly
- preview/open attachments
- show OCR text if useful
- allow editing

Key actions:
- edit record
- add another attachment
- delete attachment/record later (ask carefully)

### 5. SettingsView
Keep minimal in v1.

Possible contents:
- iCloud sync status
- app version/build info
- storage/privacy note

## Navigation flow
### Happy path
- LibraryView
- tap add
- CaptureView
- OCR processing
- EditRecordView
- save
- RecordDetailView or back to LibraryView

### Retrieval path
- LibraryView
- search
- tap matching record
- RecordDetailView

### Edit path
- RecordDetailView
- tap edit
- EditRecordView
- save
- back to RecordDetailView

## UX notes
- add flow should feel fast and low-friction
- users should never feel forced to complete every field perfectly
- search and retrieval should feel faster than hunting through Photos
- product name should be visually dominant over document metadata

## Deferred flows
Not v1 priorities:
- onboarding carousel
- family/shared libraries
- export/import flows
- multi-step advanced filtering UI
- reminder center
