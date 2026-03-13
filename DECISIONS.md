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
- Build around a simple five-screen flow: Library, Capture, Edit, Detail, Settings

### Build order choice
- Build local-first, but design with CloudKit sync in mind from the start
- Implement sync after local model, persistence, and retrieval flow are stable

### Project bootstrap choice
- Start with a plain SwiftUI app shell and add persistence deliberately
- Avoid over-relying on Xcode-generated Core Data scaffolding
