import Foundation
import SwiftData

@Model
final class PurchaseRecord {
    var id: UUID
    var productName: String
    var merchantName: String?
    var purchaseDate: Date?
    var warrantyExpiryDate: Date?
    var notes: String?
    var amount: Double?
    var currency: String?
    var category: String?
    var tagsRaw: String

    // Support info (embedded, not a separate model)
    var supportProviderName: String?
    var supportPhoneNumber: String?
    var supportConfidence: String? // "verified" or "estimated"
    var supportNote: String?

    // Notification tracking
    var warrantyNotificationScheduled: Bool

    @Relationship(deleteRule: .cascade, inverse: \Attachment.record)
    var attachments: [Attachment]

    var createdAt: Date
    var updatedAt: Date

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
        tags: [String] = [],
        supportProviderName: String? = nil,
        supportPhoneNumber: String? = nil,
        supportConfidence: String? = nil,
        supportNote: String? = nil,
        warrantyNotificationScheduled: Bool = false,
        attachments: [Attachment] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
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
        self.tagsRaw = tags.joined(separator: ",")
        self.supportProviderName = supportProviderName
        self.supportPhoneNumber = supportPhoneNumber
        self.supportConfidence = supportConfidence
        self.supportNote = supportNote
        self.warrantyNotificationScheduled = warrantyNotificationScheduled
        self.attachments = attachments
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
