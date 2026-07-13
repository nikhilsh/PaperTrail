import Foundation

/// Codable mirror of `PurchaseRecord` for the household-sharing pipeline
/// (Milestone 4 Phase 1). Deliberately excludes `warrantyNotificationScheduled`
/// and `returnWindowNotificationScheduled` — those are per-device local-
/// notification bookkeeping, not shared state. Each device (owner or member)
/// schedules its own local notifications from whatever copy of the record it
/// holds, so those two flags never travel over the wire.
struct SharedPurchaseRecordDTO: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var productName: String
    var merchantName: String?
    var notes: String?
    var currency: String?
    var category: String?
    var room: String?
    var supportProviderName: String?
    var supportPhoneNumber: String?
    var supportConfidence: String?
    var supportNote: String?
    var serialNumber: String?
    var coverageSummary: String?
    var purchaseDate: Date?
    var warrantyExpiryDate: Date?
    var amount: Double?
    var tagsRaw: String
    var returnWindowDays: Int?
    var isRegistered: Bool
    var productImageAttachmentID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        productName: String,
        merchantName: String? = nil,
        notes: String? = nil,
        currency: String? = nil,
        category: String? = nil,
        room: String? = nil,
        supportProviderName: String? = nil,
        supportPhoneNumber: String? = nil,
        supportConfidence: String? = nil,
        supportNote: String? = nil,
        serialNumber: String? = nil,
        coverageSummary: String? = nil,
        purchaseDate: Date? = nil,
        warrantyExpiryDate: Date? = nil,
        amount: Double? = nil,
        tagsRaw: String = "",
        returnWindowDays: Int? = nil,
        isRegistered: Bool = false,
        productImageAttachmentID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.productName = productName
        self.merchantName = merchantName
        self.notes = notes
        self.currency = currency
        self.category = category
        self.room = room
        self.supportProviderName = supportProviderName
        self.supportPhoneNumber = supportPhoneNumber
        self.supportConfidence = supportConfidence
        self.supportNote = supportNote
        self.serialNumber = serialNumber
        self.coverageSummary = coverageSummary
        self.purchaseDate = purchaseDate?.householdWireQuantized
        self.warrantyExpiryDate = warrantyExpiryDate?.householdWireQuantized
        self.amount = amount
        self.tagsRaw = tagsRaw
        self.returnWindowDays = returnWindowDays
        self.isRegistered = isRegistered
        self.productImageAttachmentID = productImageAttachmentID
        self.createdAt = createdAt.householdWireQuantized
        self.updatedAt = updatedAt.householdWireQuantized
    }

    /// Mirror a local `PurchaseRecord` into a DTO ready to send to
    /// `HouseholdZone`. `@MainActor` because `PurchaseRecord` is a SwiftData
    /// `@Model` and the project's default actor isolation is `MainActor`.
    @MainActor
    init(record: PurchaseRecord) {
        self.init(
            id: record.id,
            productName: record.productName,
            merchantName: record.merchantName,
            notes: record.notes,
            currency: record.currency,
            category: record.category,
            room: record.room,
            supportProviderName: record.supportProviderName,
            supportPhoneNumber: record.supportPhoneNumber,
            supportConfidence: record.supportConfidence,
            supportNote: record.supportNote,
            serialNumber: record.serialNumber,
            coverageSummary: record.coverageSummary,
            purchaseDate: record.purchaseDate,
            warrantyExpiryDate: record.warrantyExpiryDate,
            amount: record.amount,
            tagsRaw: record.tagsRaw,
            returnWindowDays: record.returnWindowDays,
            isRegistered: record.isRegistered,
            productImageAttachmentID: record.productImageAttachmentID,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Build a standalone `PurchaseRecord` from this DTO (used to render a
    /// record mirrored *to* this device — the `HouseholdCache` copy, never the
    /// SwiftData store). The two per-device notification flags are left at
    /// their default (`false`); this device schedules its own notifications
    /// if/when it needs to.
    @MainActor
    func makeModel() -> PurchaseRecord {
        PurchaseRecord(
            id: id,
            productName: productName,
            merchantName: merchantName,
            purchaseDate: purchaseDate,
            warrantyExpiryDate: warrantyExpiryDate,
            notes: notes,
            amount: amount,
            currency: currency,
            category: category,
            room: room,
            tags: tagsRaw
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            supportProviderName: supportProviderName,
            supportPhoneNumber: supportPhoneNumber,
            supportConfidence: supportConfidence,
            supportNote: supportNote,
            returnWindowDays: returnWindowDays,
            serialNumber: serialNumber,
            coverageSummary: coverageSummary,
            isRegistered: isRegistered,
            productImageAttachmentID: productImageAttachmentID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// Codable mirror of `Attachment` for the household-sharing pipeline
/// (Milestone 4 Phase 1). No image bytes here — a `CKAsset` field arrives in
/// Phase 4; this DTO only carries the metadata `Attachment` itself stores in
/// SwiftData.
struct SharedAttachmentDTO: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var recordID: UUID?
    var typeRaw: String
    var localFilename: String
    var ocrText: String?
    var createdAt: Date

    init(
        id: UUID,
        recordID: UUID? = nil,
        typeRaw: String,
        localFilename: String,
        ocrText: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordID = recordID
        self.typeRaw = typeRaw
        self.localFilename = localFilename
        self.ocrText = ocrText
        self.createdAt = createdAt.householdWireQuantized
    }

    /// `@MainActor` because `Attachment` is a SwiftData `@Model` and the
    /// project's default actor isolation is `MainActor`.
    @MainActor
    init(attachment: Attachment) {
        self.init(
            id: attachment.id,
            recordID: attachment.recordID,
            typeRaw: attachment.typeRaw,
            localFilename: attachment.localFilename,
            ocrText: attachment.ocrText,
            createdAt: attachment.createdAt
        )
    }

    /// Build a standalone `Attachment` from this DTO (the `HouseholdCache`
    /// copy, never the SwiftData store).
    @MainActor
    func makeModel() -> Attachment {
        Attachment(
            id: id,
            recordID: recordID,
            type: AttachmentType(rawValue: typeRaw) ?? .other,
            localFilename: localFilename,
            ocrText: ocrText,
            createdAt: createdAt
        )
    }
}

extension Date {
    /// All DTO dates are quantized to whole milliseconds at construction.
    /// DTO equality drives `HouseholdMirrorCoordinator.computeDiff` — if
    /// CloudKit's wire encoding rounds a timestamp even slightly, a
    /// full-precision local DTO would never equal its round-tripped cache
    /// copy and every reconcile would re-mirror the entire library forever.
    /// Quantizing both sides to the same grid makes the comparison stable.
    var householdWireQuantized: Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate * 1000).rounded() / 1000)
    }
}
