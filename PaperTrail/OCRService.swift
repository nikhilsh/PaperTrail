import Foundation
import UIKit
import Vision

protocol OCRService: Sendable {
    func extract(from image: UIImage) async throws -> OCRExtractionResult
}

/// Performs Vision OCR to get text (structured when possible), then runs the
/// extraction pipeline (Foundation Models → heuristic fallback) to extract
/// structured fields.
///
/// OCR strategy (best-first, all on-device):
/// 1. iOS 26 `RecognizeDocumentsRequest` → structured `OCRDocument` (tables,
///    reading order, structural total). See `DocumentStructureOCRService`.
/// 2. Fall back to `VNRecognizeTextRequest` (flat text) seeded with a custom
///    brand/merchant vocabulary so model numbers and store names aren't
///    "corrected" into nonsense.
struct VisionOCRService: OCRService {
    private let pipeline = ExtractionPipeline()
    private let structuredService = DocumentStructureOCRService()

    /// Extra recognizer vocabulary. Defaults to the shared brand/merchant
    /// lexicon; callers with DB access can inject learned merchant names.
    private let customWords: [String]

    init(customWords: [String] = OCRVocabulary.customWords()) {
        self.customWords = customWords
    }

    func extract(from image: UIImage) async throws -> OCRExtractionResult {
        guard let cgImage = image.cgImage else {
            return .empty
        }

        // 1. Prefer structured document recognition (iOS 26+); fall back to flat text.
        let document: OCRDocument
        if let structured = await structuredService.recognize(cgImage) {
            document = structured
        } else {
            let text = try await performRecognition(on: cgImage)
            document = .plain(text)
        }

        // 2. Run the structured extraction pipeline on the OCR document.
        let structured = await pipeline.extract(from: document)

        // 3. Bridge back to the OCRExtractionResult format the rest of the app expects.
        return structured.toOCRExtractionResult(recognizedText: document.text)
    }

    private func performRecognition(on cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Bias recognition toward known brand/model/merchant tokens so language
            // correction doesn't mangle them (e.g. "Dyson" → "Dylan").
            if !customWords.isEmpty {
                request.customWords = customWords
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
