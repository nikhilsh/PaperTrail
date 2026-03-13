import Foundation

protocol ScanningService {
    func beginCapture(for type: AttachmentType) async throws -> Attachment
}

struct PlaceholderScanningService: ScanningService {
    func beginCapture(for type: AttachmentType) async throws -> Attachment {
        Attachment(
            type: type,
            localFilename: "placeholder-\(type.rawValue).jpg",
            ocrText: previewOCRText(for: type)
        )
    }

    private func previewOCRText(for type: AttachmentType) -> String {
        switch type {
        case .receipt:
            return "Best Denki Dyson V15 Detect 2026-03-13"
        case .warranty:
            return "LG Refrigerator Warranty 2 years"
        case .invoice:
            return "Invoice placeholder"
        case .other:
            return "Imported proof image"
        }
    }
}
