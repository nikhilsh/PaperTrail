import Foundation
import UIKit

/// Saves scanned images to disk and creates Attachment records.
struct ScanningService {
    private let ocrService: any OCRService

    init(ocrService: any OCRService = VisionOCRService()) {
        self.ocrService = ocrService
    }

    /// Process scanned images: save to disk, run OCR, return attachments and combined OCR result.
    func process(images: [UIImage], type: AttachmentType) async -> (attachments: [Attachment], ocr: OCRExtractionResult) {
        var attachments: [Attachment] = []
        var allText: [String] = []
        var bestProduct: String?
        var bestMerchant: String?
        var bestDate: Date?
        var bestAmount: Double?
        var bestCurrency: String?
        var bestCategory: String?
        var bestWarrantyMonths: Int?
        var bestSource: ExtractionSource?

        for image in images {
            guard let filename = ImageStorageManager.save(image) else { continue }

            var ocrResult = OCRExtractionResult.empty
            do {
                ocrResult = try await ocrService.extract(from: image)
            } catch {
                print("OCR failed for \(filename): \(error)")
            }

            let attachment = Attachment(
                type: type,
                localFilename: filename,
                ocrText: ocrResult.recognizedText.isEmpty ? nil : ocrResult.recognizedText
            )
            attachments.append(attachment)

            if !ocrResult.recognizedText.isEmpty {
                allText.append(ocrResult.recognizedText)
            }
            if bestProduct == nil { bestProduct = ocrResult.suggestedProductName }
            if bestMerchant == nil { bestMerchant = ocrResult.suggestedMerchantName }
            if bestDate == nil { bestDate = ocrResult.suggestedPurchaseDate }
            if bestAmount == nil { bestAmount = ocrResult.suggestedAmount }
            if bestCurrency == nil { bestCurrency = ocrResult.suggestedCurrency }
            if bestCategory == nil { bestCategory = ocrResult.suggestedCategory }
            if bestWarrantyMonths == nil { bestWarrantyMonths = ocrResult.suggestedWarrantyDurationMonths }
            if bestSource == nil { bestSource = ocrResult.extractionSource }
        }

        let combined = OCRExtractionResult(
            recognizedText: allText.joined(separator: "\n---\n"),
            suggestedProductName: bestProduct,
            suggestedMerchantName: bestMerchant,
            suggestedPurchaseDate: bestDate,
            suggestedAmount: bestAmount,
            suggestedCurrency: bestCurrency,
            suggestedCategory: bestCategory,
            suggestedWarrantyDurationMonths: bestWarrantyMonths,
            extractionSource: bestSource,
            suggestedNotes: allText.isEmpty ? nil : "Extracted from scanned document."
        )

        return (attachments, combined)
    }
}
