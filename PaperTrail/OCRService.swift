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
            suggestedAmount: extractAmount(from: recognizedText),
            suggestedCurrency: extractCurrency(from: recognizedText),
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
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !looksLikeDate($0) && !looksLikeTotal($0) && !looksLikeAddress($0) && !looksLikeHeader($0) }
            .filter { $0.count >= 4 && $0.count <= 80 }

        // Skip the first line (likely merchant) and find the longest qualifying line
        let candidates = lines.dropFirst()
        return candidates.max(by: { $0.count < $1.count })
    }

    private func extractMerchantName(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count >= 3 }

        // Merchant name is typically the first non-trivial line
        // Skip lines that are just numbers or dates
        for line in lines.prefix(5) {
            if !looksLikeDate(line) && !looksLikePureNumber(line) && line.count >= 3 {
                return line
            }
        }
        return lines.first
    }

    private func extractDate(from text: String) -> Date? {
        // Try common SG/APAC date formats first: DD/MM/YYYY, DD-MM-YYYY, DD.MM.YYYY
        let sgPatterns = [
            #"(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{4})"#,  // DD/MM/YYYY
            #"(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{2})"#,   // DD/MM/YY
        ]

        for pattern in sgPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {

                let dayStr = String(text[Range(match.range(at: 1), in: text)!])
                let monthStr = String(text[Range(match.range(at: 2), in: text)!])
                var yearStr = String(text[Range(match.range(at: 3), in: text)!])

                if yearStr.count == 2 {
                    yearStr = "20" + yearStr
                }

                if let day = Int(dayStr), let month = Int(monthStr), let year = Int(yearStr),
                   day >= 1, day <= 31, month >= 1, month <= 12, year >= 2000, year <= 2099 {
                    var components = DateComponents()
                    components.day = day
                    components.month = month
                    components.year = year
                    if let date = Calendar.current.date(from: components) {
                        return date
                    }
                }
            }
        }

        // Fallback: NSDataDetector for natural language dates
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        return matches.first?.date
    }

    private func extractAmount(from text: String) -> Double? {
        // Look for total/amount lines with currency values
        let lines = text.components(separatedBy: .newlines)

        // First pass: look for lines with "total" keyword
        for line in lines.reversed() {
            let lower = line.lowercased()
            if lower.contains("total") || lower.contains("amount") || lower.contains("grand total") || lower.contains("nett") {
                if let amount = extractNumber(from: line) {
                    return amount
                }
            }
        }

        // Second pass: find the largest dollar amount (likely the total)
        var amounts: [Double] = []
        let amountPattern = #"(?:\$|SGD|S\$|MYR|RM)\s*(\d{1,}[,.]?\d{0,2})"#
        if let regex = try? NSRegularExpression(pattern: amountPattern, options: .caseInsensitive) {
            let fullText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: fullText.length))
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    let numStr = String(text[range]).replacingOccurrences(of: ",", with: "")
                    if let num = Double(numStr) {
                        amounts.append(num)
                    }
                }
            }
        }

        return amounts.max()
    }

    private func extractCurrency(from text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("sgd") || lower.contains("s$") { return "SGD" }
        if lower.contains("myr") || lower.contains("rm") { return "MYR" }
        if lower.contains("usd") || lower.contains("us$") { return "USD" }
        if lower.contains("$") { return "SGD" } // Default for SG context
        return nil
    }

    private func extractNumber(from line: String) -> Double? {
        let pattern = #"(\d{1,}[,.]?\d{0,2})\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        let numStr = String(line[range]).replacingOccurrences(of: ",", with: "")
        return Double(numStr)
    }

    // MARK: - Line classifiers

    private func looksLikeDate(_ line: String) -> Bool {
        let datePattern = #"\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}"#
        return line.range(of: datePattern, options: .regularExpression) != nil && line.count < 20
    }

    private func looksLikeTotal(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("total") || lower.contains("subtotal") || lower.contains("tax")
            || lower.contains("gst") || lower.contains("amount due") || lower.contains("change")
            || lower.contains("rounding")
    }

    private func looksLikeAddress(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("blk") || lower.contains("street") || lower.contains("road")
            || lower.contains("avenue") || lower.contains("tel:") || lower.contains("fax:")
            || lower.contains("singapore") || lower.contains("#0") || lower.contains("level")
    }

    private func looksLikeHeader(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("receipt") || lower.contains("invoice") || lower.contains("tax invoice")
            || lower.contains("bill") || lower == "qty" || lower == "item" || lower == "description"
    }

    private func looksLikePureNumber(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        return stripped.allSatisfy { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" || $0 == "/" }
    }
}
