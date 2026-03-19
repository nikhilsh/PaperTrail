import Foundation
import UIKit
import Vision

protocol OCRService: Sendable {
    func extract(from image: UIImage) async throws -> OCRExtractionResult
}

struct VisionOCRService: OCRService {
    func extract(from image: UIImage) async throws -> OCRExtractionResult {
        guard let cgImage = image.cgImage else {
            return .empty
        }

        let recognizedText = try await performRecognition(on: cgImage)

        return OCRExtractionResult(
            recognizedText: recognizedText,
            suggestedProductName: extractProductName(from: recognizedText),
            suggestedMerchantName: extractMerchantName(from: recognizedText),
            suggestedPurchaseDate: extractDate(from: recognizedText),
            suggestedNotes: recognizedText.isEmpty ? nil : "OCR draft extracted from scanned document."
        )
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

    // MARK: - Field extraction heuristics

    private func extractProductName(from text: String) -> String? {
        // Look for lines that might be product names — typically longer noun phrases
        // after filtering out obvious non-product lines (dates, totals, addresses)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !looksLikeDate($0) && !looksLikeTotal($0) && !looksLikeAddress($0) }
            .filter { $0.count >= 4 && $0.count <= 80 }

        // Return the longest qualifying line as a rough product-name guess
        return lines.max(by: { $0.count < $1.count })
    }

    private func extractMerchantName(from text: String) -> String? {
        // The merchant name is often the first non-trivial line of a receipt
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count >= 3 }

        return lines.first
    }

    private func extractDate(from text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        return matches.first?.date
    }

    private func looksLikeDate(_ line: String) -> Bool {
        let datePattern = #"\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}"#
        return line.range(of: datePattern, options: .regularExpression) != nil && line.count < 20
    }

    private func looksLikeTotal(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("total") || lower.contains("subtotal") || lower.contains("tax")
            || lower.contains("gst") || lower.contains("amount due")
    }

    private func looksLikeAddress(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("blk") || lower.contains("street") || lower.contains("road")
            || lower.contains("avenue") || lower.contains("tel:") || lower.contains("fax:")
    }
}
