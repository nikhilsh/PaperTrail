import Foundation
import UIKit

/// Saves scanned images to disk and creates Attachment records.
struct ScanningService {
    /// Explicitly injected OCR service (used by tests). When nil, a
    /// vocabulary-aware `VisionOCRService` is built per call so learned merchant
    /// names can be promoted into the recognizer's `customWords`.
    private let injectedOCRService: (any OCRService)?

    init(ocrService: (any OCRService)? = nil) {
        self.injectedOCRService = ocrService
    }

    /// Process scanned images: save to disk, run OCR, return attachments and combined OCR result.
    ///
    /// - Parameter learnedMerchants: merchant display names from the learning
    ///   loop. Promoted into Vision `customWords` so previously-seen store names
    ///   are recognized more reliably (closes the loop between learning and OCR).
    func process(images: [UIImage], type: AttachmentType, learnedMerchants: [String] = []) async -> (attachments: [Attachment], ocr: OCRExtractionResult) {
        let ocrService = injectedOCRService
            ?? VisionOCRService(customWords: OCRVocabulary.customWords(learnedMerchants: learnedMerchants))
        let barcodeService = BarcodeDetectionService()

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
        var bestDocumentKind: DocumentKind?
        var bestStructuredResult: StructuredExtractionResult?
        var bestLineItems: [LineItem] = []
        var allBarcodePayloads: [String] = []

        for image in images {
            guard let filename = ImageStorageManager.save(image) else { continue }

            var ocrResult = OCRExtractionResult.empty
            do {
                ocrResult = try await ocrService.extract(from: image)
            } catch {
                print("OCR failed for \(filename): \(error)")
            }

            // Passive barcode sweep: run alongside OCR so a serial encoded on
            // the same page (asset tag, warranty card, product box) can be
            // suggested even if it never appears in the OCR text.
            allBarcodePayloads.append(contentsOf: await barcodeService.detectPayloads(in: image))

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
            if bestDocumentKind == nil { bestDocumentKind = ocrResult.documentKind }
            if bestStructuredResult == nil { bestStructuredResult = ocrResult.structuredResult }
            if bestLineItems.isEmpty { bestLineItems = ocrResult.lineItems }
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
            suggestedNotes: NoteFacts.composeNotes(from: bestStructuredResult),
            documentKind: bestDocumentKind,
            lineItems: bestLineItems,
            serialCandidate: SerialCandidateFilter.bestCandidate(from: allBarcodePayloads),
            structuredResult: bestStructuredResult
        )

        return (attachments, combined)
    }
}
