import Foundation

protocol OCRService {
    func extractText(from attachment: Attachment) async throws -> String
}

struct PlaceholderOCRService: OCRService {
    func extractText(from attachment: Attachment) async throws -> String {
        attachment.ocrText ?? ""
    }
}
