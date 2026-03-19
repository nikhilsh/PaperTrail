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
    var typeRaw: String
    var localFilename: String
    var ocrText: String?
    var createdAt: Date

    /// Image data stored for CloudKit sync.
    /// On-device, we also cache to disk via ImageStorageManager for fast access.
    @Attribute(.externalStorage)
    var imageData: Data?

    var record: PurchaseRecord?

    var type: AttachmentType {
        get { AttachmentType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    init(
        type: AttachmentType,
        localFilename: String,
        ocrText: String? = nil,
        imageData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.typeRaw = type.rawValue
        self.localFilename = localFilename
        self.ocrText = ocrText
        self.imageData = imageData
        self.createdAt = createdAt
    }

    /// Load the image, preferring local disk cache, falling back to synced data.
    var image: UIImage? {
        // Try disk cache first (fast)
        if let cached = ImageStorageManager.load(localFilename) {
            return cached
        }
        // Fall back to synced data
        if let data = imageData, let img = UIImage(data: data) {
            // Re-cache locally for next time
            ImageStorageManager.save(img, withFilename: localFilename)
            return img
        }
        return nil
    }
}
