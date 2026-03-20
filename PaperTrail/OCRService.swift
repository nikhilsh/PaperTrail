import Foundation
import UIKit
import Vision

protocol OCRService: Sendable {
    func extract(from image: UIImage) async throws -> OCRExtractionResult
}

/// Performs Vision OCR to get raw text, then runs the extraction pipeline
/// (Foundation Models → heuristic fallback) to extract structured fields.
struct VisionOCRService: OCRService {
    private let pipeline = ExtractionPipeline()

    func extract(from image: UIImage) async throws -> OCRExtractionResult {
        guard let cgImage = image.cgImage else {
            return .empty
        }

        let recognizedText = try await performRecognition(on: cgImage)

        // Run the structured extraction pipeline on the raw OCR text.
        let structured = await pipeline.extract(from: recognizedText)

        // Bridge back to the OCRExtractionResult format the rest of the app expects.
        return structured.toOCRExtractionResult(recognizedText: recognizedText)
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

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
