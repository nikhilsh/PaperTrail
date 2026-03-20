import Foundation
import SwiftData
import UIKit

enum AttachmentType: String, Codable, Hashable, CaseIterable {
    case receipt
    case warranty
    case invoice
    case other
}

@Model
final class Attachment {
    var id: UUID
    var recordID: UUID?
    var typeRaw: String
    var localFilename: String
    var ocrText: String?
    var createdAt: Date

    var type: AttachmentType {
        get { AttachmentType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        recordID: UUID? = nil,
        type: AttachmentType,
        localFilename: String,
        ocrText: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.recordID = recordID
        self.typeRaw = type.rawValue
        self.localFilename = localFilename
        self.ocrText = ocrText
        self.createdAt = createdAt
    }

    var image: UIImage? {
        ImageStorageManager.load(localFilename)
    }
}
