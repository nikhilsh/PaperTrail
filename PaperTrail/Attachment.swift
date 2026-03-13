import Foundation

enum AttachmentType: String, Codable, Hashable {
    case receipt
    case warranty
    case invoice
    case other
}

struct Attachment: Identifiable, Hashable {
    let id: UUID
    var type: AttachmentType
    var localFilename: String
    var ocrText: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        type: AttachmentType,
        localFilename: String,
        ocrText: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.type = type
        self.localFilename = localFilename
        self.ocrText = ocrText
        self.createdAt = createdAt
    }
}

extension Attachment {
    static let preview = Attachment(
        type: .receipt,
        localFilename: "dyson-receipt.jpg",
        ocrText: "Best Denki Dyson V15 Detect"
    )
}
