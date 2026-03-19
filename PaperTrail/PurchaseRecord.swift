import Foundation
import SwiftData

@Model
final class PurchaseRecord {
    var productName: String
    var merchantName: String?
    var purchaseDate: Date?
    var warrantyExpiryDate: Date?
    var notes: String?

    // Support info (embedded, not a separate model)
    var supportProviderName: String?
    var supportPhoneNumber: String?
    var supportConfidence: String? // "verified" or "estimated"
    var supportNote: String?

    @Relationship(deleteRule: .cascade, inverse: \Attachment.record)
    var attachments: [Attachment]

    var createdAt: Date
    var updatedAt: Date

    init(
        productName: String,
        merchantName: String? = nil,
        purchaseDate: Date? = nil,
        warrantyExpiryDate: Date? = nil,
        notes: String? = nil,
        supportProviderName: String? = nil,
        supportPhoneNumber: String? = nil,
        supportConfidence: String? = nil,
        supportNote: String? = nil,
        attachments: [Attachment] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.productName = productName
        self.merchantName = merchantName
        self.purchaseDate = purchaseDate
        self.warrantyExpiryDate = warrantyExpiryDate
        self.notes = notes
        self.supportProviderName = supportProviderName
        self.supportPhoneNumber = supportPhoneNumber
        self.supportConfidence = supportConfidence
        self.supportNote = supportNote
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PurchaseRecord {
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
}
