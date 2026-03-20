import Foundation
import UIKit
import UniformTypeIdentifiers

/// Manages exporting and importing PurchaseRecord packages for sharing.
///
/// Export format: a `.papertrail` file (actually a zip) containing:
/// - `record.json` — record metadata
/// - `images/` — attachment images
struct RecordSharingManager {
    /// Export a record to a shareable file URL.
    static func exportRecord(_ record: PurchaseRecord) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let imagesDir = tempDir.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        // Build JSON payload
        var attachmentMeta: [[String: String]] = []
        for attachment in record.attachments {
            var meta: [String: String] = [
                "type": attachment.typeRaw,
                "filename": attachment.localFilename,
            ]
            if let ocrText = attachment.ocrText {
                meta["ocrText"] = ocrText
            }
            // Copy image
            if let image = attachment.image,
               let data = image.jpegData(compressionQuality: 0.85) {
                let imageURL = imagesDir.appendingPathComponent(attachment.localFilename)
                try data.write(to: imageURL)
            }
            attachmentMeta.append(meta)
        }

        let payload: [String: Any] = [
            "version": 1,
            "productName": record.productName,
            "merchantName": record.merchantName as Any,
            "purchaseDate": record.purchaseDate?.timeIntervalSince1970 as Any,
            "warrantyExpiryDate": record.warrantyExpiryDate?.timeIntervalSince1970 as Any,
            "notes": record.notes as Any,
            "amount": record.amount as Any,
            "currency": record.currency as Any,
            "category": record.category as Any,
            "tags": record.tags,
            "supportProviderName": record.supportProviderName as Any,
            "supportPhoneNumber": record.supportPhoneNumber as Any,
            "supportConfidence": record.supportConfidence as Any,
            "supportNote": record.supportNote as Any,
            "attachments": attachmentMeta,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
        try jsonData.write(to: tempDir.appendingPathComponent("record.json"))

        // Create zip
        let safeName = record.productName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .prefix(50)
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).papertrail")

        // Remove old zip if exists
        try? FileManager.default.removeItem(at: zipURL)

        // Use NSFileCoordinator to create a zip
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var resultURL: URL?

        coordinator.coordinate(readingItemAt: tempDir, options: .forUploading, error: &error) { url in
            do {
                try FileManager.default.copyItem(at: url, to: zipURL)
                resultURL = zipURL
            } catch {
                print("Failed to create zip: \(error)")
            }
        }

        if let error { throw error }

        // Clean up temp dir
        try? FileManager.default.removeItem(at: tempDir)

        guard let url = resultURL else {
            throw SharingError.exportFailed
        }
        return url
    }

    /// Import a record from a `.papertrail` file.
    static func importRecord(from url: URL) async throws -> ImportedRecord {
        // Current v1 import path supports direct JSON payloads.
        // The export path currently produces a coordinated archive for sharing,
        // but in-app import is intentionally conservative until a proper unzip path
        // is implemented for iOS.
        let data = try Data(contentsOf: url)

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return try parseJSON(json, imagesDir: nil)
        }

        throw SharingError.importFailed
    }

    private static func parseJSON(_ json: [String: Any], imagesDir: URL?) throws -> ImportedRecord {
        guard let productName = json["productName"] as? String else {
            throw SharingError.importFailed
        }

        var attachments: [(type: AttachmentType, filename: String, ocrText: String?, imageData: Data?)] = []
        if let attachmentMeta = json["attachments"] as? [[String: String]] {
            for meta in attachmentMeta {
                let type = AttachmentType(rawValue: meta["type"] ?? "other") ?? .other
                let filename = meta["filename"] ?? UUID().uuidString + ".jpg"
                let ocrText = meta["ocrText"]
                var imageData: Data?
                if let imagesDir {
                    imageData = try? Data(contentsOf: imagesDir.appendingPathComponent(filename))
                }
                attachments.append((type, filename, ocrText, imageData))
            }
        }

        return ImportedRecord(
            productName: productName,
            merchantName: json["merchantName"] as? String,
            purchaseDate: (json["purchaseDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) },
            warrantyExpiryDate: (json["warrantyExpiryDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) },
            notes: json["notes"] as? String,
            amount: json["amount"] as? Double,
            currency: json["currency"] as? String,
            category: json["category"] as? String,
            tags: json["tags"] as? [String] ?? [],
            supportProviderName: json["supportProviderName"] as? String,
            supportPhoneNumber: json["supportPhoneNumber"] as? String,
            supportConfidence: json["supportConfidence"] as? String,
            supportNote: json["supportNote"] as? String,
            attachments: attachments
        )
    }
}

struct ImportedRecord {
    let productName: String
    let merchantName: String?
    let purchaseDate: Date?
    let warrantyExpiryDate: Date?
    let notes: String?
    let amount: Double?
    let currency: String?
    let category: String?
    let tags: [String]
    let supportProviderName: String?
    let supportPhoneNumber: String?
    let supportConfidence: String?
    let supportNote: String?
    let attachments: [(type: AttachmentType, filename: String, ocrText: String?, imageData: Data?)]

    /// Create a PurchaseRecord from the import.
    func toPurchaseRecord() -> PurchaseRecord {
        let record = PurchaseRecord(
            productName: productName,
            merchantName: merchantName,
            purchaseDate: purchaseDate,
            warrantyExpiryDate: warrantyExpiryDate,
            notes: notes,
            amount: amount,
            currency: currency,
            category: category,
            tags: tags,
            supportProviderName: supportProviderName,
            supportPhoneNumber: supportPhoneNumber,
            supportConfidence: supportConfidence,
            supportNote: supportNote
        )

        for att in attachments {
            let attachment = Attachment(
                type: att.type,
                localFilename: att.filename,
                ocrText: att.ocrText
            )
            attachment.record = record
            record.attachments.append(attachment)
        }

        return record
    }
}

enum SharingError: LocalizedError {
    case exportFailed
    case importFailed

    var errorDescription: String? {
        switch self {
        case .exportFailed: "Failed to export record."
        case .importFailed: "Failed to import record. The file may be corrupted."
        }
    }
}
