import Testing
import Foundation
import CloudKit
@testable import PaperTrail

/// Coverage for `SharedRecordMapper`'s DTO ⇄ `CKRecord` round trip (Milestone
/// 4 Phase 1 — household record sharing). No live CloudKit container is
/// touched; `CKRecord` instances here are constructed purely in-memory.
struct SharedRecordMapperTests {

    private let zoneID = HouseholdSchema.ownerZoneID

    // MARK: - Purchase record round trip

    private func fullyPopulatedPurchaseDTO() -> SharedPurchaseRecordDTO {
        SharedPurchaseRecordDTO(
            id: UUID(),
            productName: "LG Washer",
            merchantName: "Gain City",
            notes: "Bought during sale",
            currency: "SGD",
            category: "Appliances",
            room: "Laundry",
            supportProviderName: "LG Support",
            supportPhoneNumber: "1800-555-0100",
            supportConfidence: "verified",
            supportNote: "Call between 9-6",
            serialNumber: "SN-9XK42",
            coverageSummary: "Parts & labor",
            purchaseDate: Date(timeIntervalSince1970: 1_747_000_000),
            warrantyExpiryDate: Date(timeIntervalSince1970: 1_810_000_000),
            amount: 1479.0,
            tagsRaw: "white goods,appliance",
            returnWindowDays: 30,
            isRegistered: true,
            productImageAttachmentID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_746_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_746_500_000)
        )
    }

    @Test func purchaseRecordFullRoundTrip() throws {
        let dto = fullyPopulatedPurchaseDTO()
        let record = SharedRecordMapper.makeCKRecord(from: dto, zoneID: zoneID)
        let decoded = try #require(SharedRecordMapper.makePurchaseDTO(from: record))
        #expect(decoded == dto)
    }

    @Test func purchaseRecordMinimalRoundTrip() throws {
        let dto = SharedPurchaseRecordDTO(
            id: UUID(),
            productName: "Toaster",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let record = SharedRecordMapper.makeCKRecord(from: dto, zoneID: zoneID)
        let decoded = try #require(SharedRecordMapper.makePurchaseDTO(from: record))
        #expect(decoded == dto)
        #expect(decoded.merchantName == nil)
        #expect(decoded.returnWindowDays == nil)
        #expect(decoded.productImageAttachmentID == nil)
        #expect(decoded.isRegistered == false)
    }

    @Test func purchaseRecordMalformedRecordReturnsNil() {
        let recordID = CKRecord.ID(recordName: "rec-not-a-real-record", zoneID: zoneID)
        let record = CKRecord(recordType: HouseholdSchema.RecordType.purchaseRecord, recordID: recordID)
        // Missing id, productName, createdAt, updatedAt entirely.
        #expect(SharedRecordMapper.makePurchaseDTO(from: record) == nil)
    }

    @Test func purchaseRecordInvalidIDStringReturnsNil() {
        let recordID = CKRecord.ID(recordName: "rec-bad", zoneID: zoneID)
        let record = CKRecord(recordType: HouseholdSchema.RecordType.purchaseRecord, recordID: recordID)
        record[HouseholdSchema.PurchaseField.id.rawValue] = "not-a-uuid" as CKRecordValue
        record[HouseholdSchema.PurchaseField.productName.rawValue] = "Toaster" as CKRecordValue
        record[HouseholdSchema.PurchaseField.createdAt.rawValue] = Date() as CKRecordValue
        record[HouseholdSchema.PurchaseField.updatedAt.rawValue] = Date() as CKRecordValue
        #expect(SharedRecordMapper.makePurchaseDTO(from: record) == nil)
    }

    @Test func applyOntoExistingRecordClearsNilledFields() throws {
        // Simulates the update path: the engine applies a DTO onto the
        // last-known server record, and fields the user cleared must clear
        // on the CKRecord too — not linger from the previous save.
        var dto = fullyPopulatedPurchaseDTO()
        let record = SharedRecordMapper.makeCKRecord(from: dto, zoneID: zoneID)

        dto.merchantName = nil
        dto.returnWindowDays = nil
        dto.productImageAttachmentID = nil
        dto.notes = "updated"
        SharedRecordMapper.apply(dto, to: record)

        #expect(record[HouseholdSchema.PurchaseField.merchantName.rawValue] == nil)
        #expect(record[HouseholdSchema.PurchaseField.returnWindowDays.rawValue] == nil)
        #expect(record[HouseholdSchema.PurchaseField.productImageAttachmentID.rawValue] == nil)
        let decoded = try #require(SharedRecordMapper.makePurchaseDTO(from: record))
        #expect(decoded == dto)
    }

    @Test func purchaseRecordDeterministicRecordName() {
        let id = UUID()
        let dto = SharedPurchaseRecordDTO(id: id, productName: "Toaster")
        let record = SharedRecordMapper.makeCKRecord(from: dto, zoneID: zoneID)
        #expect(record.recordID.recordName == "rec-\(id.uuidString)")
    }

    // MARK: - Attachment round trip

    private func fullyPopulatedAttachmentDTO() -> SharedAttachmentDTO {
        SharedAttachmentDTO(
            id: UUID(),
            recordID: UUID(),
            typeRaw: AttachmentType.receipt.rawValue,
            localFilename: "abc123.jpg",
            ocrText: "Total: $42.00",
            createdAt: Date(timeIntervalSince1970: 1_746_000_000)
        )
    }

    @Test func attachmentFullRoundTrip() throws {
        let dto = fullyPopulatedAttachmentDTO()
        let record = SharedRecordMapper.makeCKRecord(from: dto, zoneID: zoneID)
        let decoded = try #require(SharedRecordMapper.makeAttachmentDTO(from: record))
        #expect(decoded == dto)
    }

    @Test func attachmentMinimalRoundTrip() throws {
        let dto = SharedAttachmentDTO(
            id: UUID(),
            typeRaw: AttachmentType.other.rawValue,
            localFilename: "xyz.jpg",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let record = SharedRecordMapper.makeCKRecord(from: dto, zoneID: zoneID)
        let decoded = try #require(SharedRecordMapper.makeAttachmentDTO(from: record))
        #expect(decoded == dto)
        #expect(decoded.recordID == nil)
        #expect(decoded.ocrText == nil)
    }

    @Test func attachmentMalformedRecordReturnsNil() {
        let recordID = CKRecord.ID(recordName: "att-not-a-real-record", zoneID: zoneID)
        let record = CKRecord(recordType: HouseholdSchema.RecordType.attachment, recordID: recordID)
        // Missing id, typeRaw, localFilename, createdAt entirely.
        #expect(SharedRecordMapper.makeAttachmentDTO(from: record) == nil)
    }

    @Test func attachmentDeterministicRecordName() {
        let id = UUID()
        let dto = SharedAttachmentDTO(id: id, typeRaw: AttachmentType.other.rawValue, localFilename: "f.jpg")
        let record = SharedRecordMapper.makeCKRecord(from: dto, zoneID: zoneID)
        #expect(record.recordID.recordName == "att-\(id.uuidString)")
    }

    // MARK: - DTO ⇄ model conversion

    @Test @MainActor func purchaseRecordDTOToModelRoundTrip() throws {
        let dto = fullyPopulatedPurchaseDTO()
        let model = dto.makeModel()
        #expect(model.id == dto.id)
        #expect(model.productName == dto.productName)
        #expect(model.merchantName == dto.merchantName)
        #expect(model.tags == ["white goods", "appliance"])
        #expect(model.returnWindowDays == dto.returnWindowDays)
        #expect(model.isRegistered == dto.isRegistered)
        #expect(model.serialNumber == dto.serialNumber)
        #expect(model.productImageAttachmentID == dto.productImageAttachmentID)
        // Per-device notification flags are never carried by the DTO — a
        // freshly-materialized model always starts unscheduled.
        #expect(model.warrantyNotificationScheduled == false)
        #expect(model.returnWindowNotificationScheduled == false)

        let roundTripped = SharedPurchaseRecordDTO(record: model)
        #expect(roundTripped == dto)
    }

    @Test @MainActor func attachmentDTOToModelRoundTrip() throws {
        let dto = fullyPopulatedAttachmentDTO()
        let model = dto.makeModel()
        #expect(model.id == dto.id)
        #expect(model.recordID == dto.recordID)
        #expect(model.type == AttachmentType.receipt)
        #expect(model.localFilename == dto.localFilename)
        #expect(model.ocrText == dto.ocrText)

        let roundTripped = SharedAttachmentDTO(attachment: model)
        #expect(roundTripped == dto)
    }
}
