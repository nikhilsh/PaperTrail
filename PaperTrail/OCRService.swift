import Foundation
#if canImport(Vision)
import Vision
#endif

protocol OCRService {
    func extract(from attachment: Attachment) async throws -> OCRExtractionResult
}

struct VisionOCRService: OCRService {
    func extract(from attachment: Attachment) async throws -> OCRExtractionResult {
        // Real Vision OCR will be wired once capture supplies actual file/image data.
        // For now, keep the service boundary and return seeded text when available.
        let text = attachment.ocrText ?? ""
        return OCRExtractionResult(
            recognizedText: text,
            suggestedProductName: text.isEmpty ? nil : guessProductName(from: text),
            suggestedMerchantName: text.isEmpty ? nil : guessMerchantName(from: text),
            suggestedPurchaseDate: nil,
            suggestedNotes: text.isEmpty ? nil : "OCR draft extracted from captured proof."
        )
    }

    private func guessProductName(from text: String) -> String? {
        if text.localizedCaseInsensitiveContains("Dyson") {
            return "Dyson V15 Detect"
        }
        return nil
    }

    private func guessMerchantName(from text: String) -> String? {
        if text.localizedCaseInsensitiveContains("Best Denki") {
            return "Best Denki"
        }
        return nil
    }
}
