import Foundation
import SwiftData

@Model
final class PurchaseRecord {
    var id: UUID = UUID()
    var productName: String = ""
    var merchantName: String?
    var purchaseDate: Date?
    var warrantyExpiryDate: Date?
    var notes: String?
    var amount: Double?
    var currency: String?
    var category: String?
    /// The room/location the item lives in (e.g. "Living Room"). Distinct from
    /// `category` (what the item is). Free-form so custom rooms persist; see RoomOptions.
    var room: String?
    var tagsRaw: String = ""

    // Support info (embedded, not a separate model)
    var supportProviderName: String?
    var supportPhoneNumber: String?
    var supportConfidence: String? // "verified" or "estimated"
    var supportNote: String?

    // Notification tracking
    var warrantyNotificationScheduled: Bool = false
    /// Tracks whether a return-window reminder has been scheduled, so we don't
    /// double-schedule on re-save. Mirrors `warrantyNotificationScheduled`.
    var returnWindowNotificationScheduled: Bool = false

    // Trust / claim fields (added in the Settings & Trust wave). All optional or
    // defaulted so existing CloudKit records migrate via lightweight migration.
    /// Manufacturer serial / model-specific ID. Surfaced in Detail + Claim Packet.
    var serialNumber: String?
    /// Human coverage text, e.g. "Parts & labor", "Parts, labor & accidental".
    var coverageSummary: String?
    /// Whether the product has been registered with the manufacturer.
    var isRegistered: Bool = false
    /// Optional third proof image — a photo of the item itself, alongside the
    /// receipt and warranty card. Links to an Attachment by id.
    var productImageAttachmentID: UUID?

    // NOTE: No @Relationship to Attachment. Both models share one CloudKit-backed store,
    // but we intentionally avoid @Relationship to keep the schema simple and avoid
    // SwiftData relationship issues with CloudKit. Link via Attachment.recordID == PurchaseRecord.id.

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        productName: String,
        merchantName: String? = nil,
        purchaseDate: Date? = nil,
        warrantyExpiryDate: Date? = nil,
        notes: String? = nil,
        amount: Double? = nil,
        currency: String? = nil,
        category: String? = nil,
        room: String? = nil,
        tags: [String] = [],
        supportProviderName: String? = nil,
        supportPhoneNumber: String? = nil,
        supportConfidence: String? = nil,
        supportNote: String? = nil,
        warrantyNotificationScheduled: Bool = false,
        returnWindowNotificationScheduled: Bool = false,
        serialNumber: String? = nil,
        coverageSummary: String? = nil,
        isRegistered: Bool = false,
        productImageAttachmentID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.productName = productName
        self.merchantName = merchantName
        self.purchaseDate = purchaseDate
        self.warrantyExpiryDate = warrantyExpiryDate
        self.notes = notes
        self.amount = amount
        self.currency = currency
        self.category = category
        self.room = room
        self.tagsRaw = tags.joined(separator: ",")
        self.supportProviderName = supportProviderName
        self.supportPhoneNumber = supportPhoneNumber
        self.supportConfidence = supportConfidence
        self.supportNote = supportNote
        self.warrantyNotificationScheduled = warrantyNotificationScheduled
        self.returnWindowNotificationScheduled = returnWindowNotificationScheduled
        self.serialNumber = serialNumber
        self.coverageSummary = coverageSummary
        self.isRegistered = isRegistered
        self.productImageAttachmentID = productImageAttachmentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PurchaseRecord {

    var tags: [String] {
        get {
            tagsRaw
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsRaw = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
        }
    }
    var supportInfo: SupportInfo? {
        guard let name = supportProviderName, let phone = supportPhoneNumber, let conf = supportConfidence else {
            return nil
        }
        return SupportInfo(
            providerName: name,
            phoneNumber: phone,
            confidence: SupportInfoConfidence(rawValue: conf) ?? .estimated,
            note: supportNote
        )
    }

    func setSupportInfo(_ info: SupportInfo?) {
        supportProviderName = info?.providerName
        supportPhoneNumber = info?.phoneNumber
        supportConfidence = info?.confidence.rawValue
        supportNote = info?.note
    }

    /// Formatted display string for amount + currency.
    var formattedAmount: String? {
        guard let amount else { return nil }
        let cur = currency ?? "SGD"
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = cur
        return formatter.string(from: NSNumber(value: amount))
    }

    /// Warranty status for display.
    var warrantyStatus: WarrantyStatus {
        guard let exp = warrantyExpiryDate else { return .unknown }
        if exp < .now { return .expired }
        let cutoff = Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now
        if exp <= cutoff { return .expiringSoon }
        return .active
    }
}

enum WarrantyStatus {
    case active, expiringSoon, expired, unknown

    var label: String {
        switch self {
        case .active: "Active"
        case .expiringSoon: "Expiring soon"
        case .expired: "Expired"
        case .unknown: "Unknown"
        }
    }

    var color: String {
        switch self {
        case .active: "green"
        case .expiringSoon: "orange"
        case .expired: "red"
        case .unknown: "secondary"
        }
    }
}
