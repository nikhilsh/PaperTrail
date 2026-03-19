import Foundation
import SwiftData

enum AttachmentType: String, Codable, Hashable, CaseIterable {
    case receipt
    case warranty
    case invoice
    case other
}

@Model
final class Attachment {
    var typeRaw: String
    var localFilename: String
    var ocrText: String?
    var createdAt: Date

    var record: PurchaseRecord?

    var type: AttachmentType {
        get { AttachmentType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    init(
        type: AttachmentType,
        localFilename: String,
        ocrText: String? = nil,
        createdAt: Date = .now
    ) {
        self.typeRaw = type.rawValue
        self.localFilename = localFilename
        self.ocrText = ocrText
        self.createdAt = createdAt
    }
}
