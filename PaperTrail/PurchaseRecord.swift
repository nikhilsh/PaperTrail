import Foundation

struct PurchaseRecord: Identifiable, Hashable {
    let id: UUID
    var productName: String
    var merchantName: String?
    var purchaseDate: Date?
    var warrantyExpiryDate: Date?
    var notes: String?
    var supportInfo: SupportInfo?
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
        supportInfo: SupportInfo? = nil,
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
        self.supportInfo = supportInfo
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension PurchaseRecord {
    static let preview = PurchaseRecord(
        productName: "Dyson V15 Detect",
        merchantName: "Best Denki",
        purchaseDate: Calendar.current.date(byAdding: .month, value: -2, to: .now),
        warrantyExpiryDate: Calendar.current.date(byAdding: .year, value: 2, to: .now),
        notes: "Receipt captured in-store after purchase.",
        supportInfo: SupportInfo(
            providerName: "Dyson Support",
            phoneNumber: "+65 7000 435754",
            confidence: .estimated,
            note: "Estimated from manufacturer support lookup, not verified from receipt."
        ),
        attachments: [.preview]
    )
}
