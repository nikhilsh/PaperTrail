# Domain Model

## Goals
The v1 model should be:
- simple
- durable
- easy to map to Core Data
- flexible enough for OCR-assisted capture and future iCloud sync

Avoid over-modeling too early.

## Core domain types

### PurchaseRecord
Represents a product-centric record that users search for later.

Suggested fields:
- `id: UUID`
- `productName: String`
- `merchantName: String?`
- `purchaseDate: Date?`
- `warrantyExpiryDate: Date?`
- `warrantyDurationMonths: Int?`
- `category: String?`
- `notes: String?`
- `createdAt: Date`
- `updatedAt: Date`
- `attachments: [Attachment]`

### Attachment
Represents a receipt, warranty card, invoice, or related proof image/document.

Suggested fields:
- `id: UUID`
- `purchaseRecordID: UUID`
- `type: AttachmentType`
- `localFilename: String`
- `ocrText: String?`
- `createdAt: Date`

### AttachmentType
Use a small enum:
- `receipt`
- `warranty`
- `invoice`
- `other`

## Searchable fields
For v1, search should work across:
- `productName`
- `merchantName`
- `notes`
- `category`
- `ocrText` from attachments

This can be implemented with a denormalized search string later if needed, but the domain model should not depend on that optimization.

## Not in v1 domain model
Avoid adding these too early:
- separate `Tag` entity
- merchant normalization tables
- warranty provider models
- user account/profile models
- sync conflict domain objects

## Persistence guidance
Core Data entities should likely mirror:
- `PurchaseRecordEntity`
- `AttachmentEntity`

But the app code should prefer plain domain models over leaking persistence types everywhere.

## File storage guidance
Store image/document files on disk and store references in persistence.
Avoid large binary blobs in Core Data unless proven necessary.

## Validation rules
### PurchaseRecord
- must have at least one attachment or enough manual metadata to be useful
- `productName` can start as a placeholder if OCR/manual review is incomplete
- `updatedAt` should change on every user edit

### Attachment
- must belong to exactly one purchase record
- must have a stable local file reference

## Future model extensions
Possible later additions:
- tags
- warranty reminders
- merchant suggestions
- extracted line-item parsing
- multiple warranty periods or service plans
