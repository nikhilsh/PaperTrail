import CloudKit
import Foundation

/// Pure DTO ⇄ `CKRecord` mapping for the household-sharing pipeline
/// (Milestone 4 Phase 1). No CloudKit network I/O here — `HouseholdSyncEngine`
/// owns that; these functions only build/parse `CKRecord`s, which keeps them
/// trivially unit-testable without a live container.
///
/// `Bool` and `Int` fields are stored as `Int64` on the `CKRecord` — CloudKit's
/// `CKRecordValue` bridging for `Bool` is awkward to pin down without a live
/// SDK to check against, so `Int64` sidesteps the ambiguity entirely and
/// round-trips cleanly either way.
enum SharedRecordMapper {

    // MARK: - Purchase record

    static func makeCKRecord(from dto: SharedPurchaseRecordDTO, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: HouseholdSchema.RecordName.purchaseRecord(dto.id), zoneID: zoneID)
        let record = CKRecord(recordType: HouseholdSchema.RecordType.purchaseRecord, recordID: recordID)
        apply(dto, to: record)
        return record
    }

    /// Write every DTO field onto `record`, explicitly clearing fields whose
    /// DTO value is nil. Updates must go onto the last-known *server* record
    /// (which carries the change tag — see `HouseholdSyncEngine`), and there a
    /// skipped assignment would leave a stale value behind: clearing a field
    /// on one device would never propagate to the others.
    static func apply(_ dto: SharedPurchaseRecordDTO, to record: CKRecord) {
        record[HouseholdSchema.PurchaseField.id.rawValue] = dto.id.uuidString as CKRecordValue
        record[HouseholdSchema.PurchaseField.productName.rawValue] = dto.productName as CKRecordValue
        record[HouseholdSchema.PurchaseField.tagsRaw.rawValue] = dto.tagsRaw as CKRecordValue
        record[HouseholdSchema.PurchaseField.isRegistered.rawValue] = Int64(dto.isRegistered ? 1 : 0) as CKRecordValue
        record[HouseholdSchema.PurchaseField.createdAt.rawValue] = dto.createdAt as CKRecordValue
        record[HouseholdSchema.PurchaseField.updatedAt.rawValue] = dto.updatedAt as CKRecordValue

        record[HouseholdSchema.PurchaseField.merchantName.rawValue] = dto.merchantName.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.notes.rawValue] = dto.notes.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.currency.rawValue] = dto.currency.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.category.rawValue] = dto.category.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.room.rawValue] = dto.room.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.supportProviderName.rawValue] = dto.supportProviderName.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.supportPhoneNumber.rawValue] = dto.supportPhoneNumber.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.supportConfidence.rawValue] = dto.supportConfidence.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.supportNote.rawValue] = dto.supportNote.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.serialNumber.rawValue] = dto.serialNumber.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.coverageSummary.rawValue] = dto.coverageSummary.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.purchaseDate.rawValue] = dto.purchaseDate.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.warrantyExpiryDate.rawValue] = dto.warrantyExpiryDate.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.amount.rawValue] = dto.amount.map { $0 as CKRecordValue }
        record[HouseholdSchema.PurchaseField.returnWindowDays.rawValue] = dto.returnWindowDays.map { Int64($0) as CKRecordValue }
        record[HouseholdSchema.PurchaseField.productImageAttachmentID.rawValue] = dto.productImageAttachmentID.map { $0.uuidString as CKRecordValue }
    }

    /// Parse a `SharedPurchaseRecordDTO` from a fetched `CKRecord`. Returns
    /// `nil` (and logs) if a required field is missing or malformed; optional
    /// fields tolerate absence.
    static func makePurchaseDTO(from record: CKRecord) -> SharedPurchaseRecordDTO? {
        guard let idString = record[HouseholdSchema.PurchaseField.id.rawValue] as? String,
              let id = UUID(uuidString: idString) else {
            AppLogger.error("Malformed SharedPurchaseRecord: missing/invalid id on \(record.recordID.recordName)", category: "cloud.sharing")
            return nil
        }
        guard let productName = record[HouseholdSchema.PurchaseField.productName.rawValue] as? String else {
            AppLogger.error("Malformed SharedPurchaseRecord: missing productName on \(record.recordID.recordName)", category: "cloud.sharing")
            return nil
        }
        guard let createdAt = record[HouseholdSchema.PurchaseField.createdAt.rawValue] as? Date else {
            AppLogger.error("Malformed SharedPurchaseRecord: missing createdAt on \(record.recordID.recordName)", category: "cloud.sharing")
            return nil
        }
        guard let updatedAt = record[HouseholdSchema.PurchaseField.updatedAt.rawValue] as? Date else {
            AppLogger.error("Malformed SharedPurchaseRecord: missing updatedAt on \(record.recordID.recordName)", category: "cloud.sharing")
            return nil
        }

        let isRegisteredValue = record[HouseholdSchema.PurchaseField.isRegistered.rawValue] as? Int64
        let returnWindowDaysValue = record[HouseholdSchema.PurchaseField.returnWindowDays.rawValue] as? Int64
        let productImageAttachmentIDString = record[HouseholdSchema.PurchaseField.productImageAttachmentID.rawValue] as? String

        return SharedPurchaseRecordDTO(
            id: id,
            productName: productName,
            merchantName: record[HouseholdSchema.PurchaseField.merchantName.rawValue] as? String,
            notes: record[HouseholdSchema.PurchaseField.notes.rawValue] as? String,
            currency: record[HouseholdSchema.PurchaseField.currency.rawValue] as? String,
            category: record[HouseholdSchema.PurchaseField.category.rawValue] as? String,
            room: record[HouseholdSchema.PurchaseField.room.rawValue] as? String,
            supportProviderName: record[HouseholdSchema.PurchaseField.supportProviderName.rawValue] as? String,
            supportPhoneNumber: record[HouseholdSchema.PurchaseField.supportPhoneNumber.rawValue] as? String,
            supportConfidence: record[HouseholdSchema.PurchaseField.supportConfidence.rawValue] as? String,
            supportNote: record[HouseholdSchema.PurchaseField.supportNote.rawValue] as? String,
            serialNumber: record[HouseholdSchema.PurchaseField.serialNumber.rawValue] as? String,
            coverageSummary: record[HouseholdSchema.PurchaseField.coverageSummary.rawValue] as? String,
            purchaseDate: record[HouseholdSchema.PurchaseField.purchaseDate.rawValue] as? Date,
            warrantyExpiryDate: record[HouseholdSchema.PurchaseField.warrantyExpiryDate.rawValue] as? Date,
            amount: record[HouseholdSchema.PurchaseField.amount.rawValue] as? Double,
            tagsRaw: record[HouseholdSchema.PurchaseField.tagsRaw.rawValue] as? String ?? "",
            returnWindowDays: returnWindowDaysValue.map { Int($0) },
            isRegistered: (isRegisteredValue ?? 0) != 0,
            productImageAttachmentID: productImageAttachmentIDString.flatMap { UUID(uuidString: $0) },
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Attachment

    static func makeCKRecord(from dto: SharedAttachmentDTO, zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: HouseholdSchema.RecordName.attachment(dto.id), zoneID: zoneID)
        let record = CKRecord(recordType: HouseholdSchema.RecordType.attachment, recordID: recordID)
        apply(dto, to: record)
        return record
    }

    /// See `apply(_:to:)` on the purchase-record side — same nil-clearing
    /// contract, needed when updating a previously-fetched server record.
    static func apply(_ dto: SharedAttachmentDTO, to record: CKRecord) {
        record[HouseholdSchema.AttachmentField.id.rawValue] = dto.id.uuidString as CKRecordValue
        record[HouseholdSchema.AttachmentField.typeRaw.rawValue] = dto.typeRaw as CKRecordValue
        record[HouseholdSchema.AttachmentField.localFilename.rawValue] = dto.localFilename as CKRecordValue
        record[HouseholdSchema.AttachmentField.createdAt.rawValue] = dto.createdAt as CKRecordValue
        record[HouseholdSchema.AttachmentField.recordID.rawValue] = dto.recordID.map { $0.uuidString as CKRecordValue }
        record[HouseholdSchema.AttachmentField.ocrText.rawValue] = dto.ocrText.map { $0 as CKRecordValue }
    }

    static func makeAttachmentDTO(from record: CKRecord) -> SharedAttachmentDTO? {
        guard let idString = record[HouseholdSchema.AttachmentField.id.rawValue] as? String,
              let id = UUID(uuidString: idString) else {
            AppLogger.error("Malformed SharedAttachment: missing/invalid id on \(record.recordID.recordName)", category: "cloud.sharing")
            return nil
        }
        guard let typeRaw = record[HouseholdSchema.AttachmentField.typeRaw.rawValue] as? String else {
            AppLogger.error("Malformed SharedAttachment: missing typeRaw on \(record.recordID.recordName)", category: "cloud.sharing")
            return nil
        }
        guard let localFilename = record[HouseholdSchema.AttachmentField.localFilename.rawValue] as? String else {
            AppLogger.error("Malformed SharedAttachment: missing localFilename on \(record.recordID.recordName)", category: "cloud.sharing")
            return nil
        }
        guard let createdAt = record[HouseholdSchema.AttachmentField.createdAt.rawValue] as? Date else {
            AppLogger.error("Malformed SharedAttachment: missing createdAt on \(record.recordID.recordName)", category: "cloud.sharing")
            return nil
        }

        let recordIDString = record[HouseholdSchema.AttachmentField.recordID.rawValue] as? String

        return SharedAttachmentDTO(
            id: id,
            recordID: recordIDString.flatMap { UUID(uuidString: $0) },
            typeRaw: typeRaw,
            localFilename: localFilename,
            ocrText: record[HouseholdSchema.AttachmentField.ocrText.rawValue] as? String,
            createdAt: createdAt
        )
    }
}
