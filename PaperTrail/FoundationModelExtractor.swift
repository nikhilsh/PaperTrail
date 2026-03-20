import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Document kind

/// Classifies the type of scanned document to guide downstream extraction and display.
enum DocumentKind: String, Codable, Sendable, Hashable, CaseIterable {
    case receipt
    case invoice
    case warrantyCard
    case orderConfirmation
    case packingSlip
    case supportDocument
    case manual
    case unknown
    
    /// Human-readable label for display.
    var label: String {
        switch self {
        case .receipt: "Receipt"
        case .invoice: "Invoice"
        case .warrantyCard: "Warranty Card"
        case .orderConfirmation: "Order Confirmation"
        case .packingSlip: "Packing Slip"
        case .supportDocument: "Support Document"
        case .manual: "Manual"
        case .unknown: "Unknown"
        }
    }
}

// MARK: - Extraction confidence

/// Indicates how confident the extraction layer is about a particular field value.
enum ExtractionConfidence: String, Codable, Sendable, Hashable {
    /// The model returned the field with high confidence.
    case high
    /// The model returned the field but flagged uncertainty.
    case medium
    /// Derived from heuristic fallback, not the Foundation Model.
    case heuristic
    /// Low confidence — suggest but flag for review.
    case low
    /// No value could be extracted.
    case none
    
    /// Whether this confidence level warrants a review cue in the UI.
    var needsReview: Bool {
        switch self {
        case .high: false
        case .medium, .heuristic, .low: true
        case .none: false // nothing to review if no value
        }
    }
    
    /// SF Symbol name for the confidence badge.
    var badgeIcon: String? {
        switch self {
        case .high: nil
        case .medium: "eye.trianglebadge.exclamationmark"
        case .heuristic: "text.magnifyingglass"
        case .low: "questionmark.circle"
        case .none: nil
        }
    }
    
    /// Short label for the confidence badge.
    var badgeLabel: String? {
        switch self {
        case .high: nil
        case .medium: "Review"
        case .heuristic: "Pattern match"
        case .low: "Suggested"
        case .none: nil
        }
    }
}

// MARK: - Structured extraction result

/// A single extracted field with its value and confidence.
struct ExtractedField<T: Sendable & Hashable>: Sendable, Hashable {
    let value: T?
    let confidence: ExtractionConfidence

    static var absent: ExtractedField<T> {
        ExtractedField(value: nil, confidence: .none)
    }
}

/// The complete set of fields extracted from OCR text, with per-field confidence.
struct StructuredExtractionResult: Sendable, Hashable {
    var documentKind: ExtractedField<DocumentKind>
    var productName: ExtractedField<String>
    var merchantName: ExtractedField<String>
    var purchaseDate: ExtractedField<Date>
    var amount: ExtractedField<Double>
    var currency: ExtractedField<String>
    var category: ExtractedField<String>
    var warrantyDurationMonths: ExtractedField<Int>

    /// Which extraction backend produced this result.
    var source: ExtractionSource

    static let empty = StructuredExtractionResult(
        documentKind: .absent,
        productName: .absent,
        merchantName: .absent,
        purchaseDate: .absent,
        amount: .absent,
        currency: .absent,
        category: .absent,
        warrantyDurationMonths: .absent,
        source: .none
    )
}

enum ExtractionSource: String, Sendable, Hashable {
    /// Apple Foundation Models on-device LLM.
    case foundationModel
    /// Regex/heuristic fallback (the existing VisionOCRService logic).
    case heuristic
    /// No extraction was attempted or all paths failed.
    case none
}

// MARK: - Foundation Model schema types

/// The schema that the on-device Foundation Model should produce.
/// Conforms to `Codable` so it can be used with `@Generable` structured output.
///
/// Field names are kept short and JSON-friendly for the model's constrained output.
#if canImport(FoundationModels)
@Generable
struct ReceiptExtractionSchema: Sendable {
    @Guide(description: "The type of document: one of receipt, invoice, warranty_card, order_confirmation, packing_slip, support_document, manual, unknown.")
    var documentKind: String?

    @Guide(description: "The product or device name purchased. If multiple items, pick the most expensive or prominent one.")
    var productName: String?

    @Guide(description: "The merchant or store name.")
    var merchantName: String?

    @Guide(description: "The purchase date in ISO 8601 format (YYYY-MM-DD).")
    var purchaseDate: String?

    @Guide(description: "The total amount paid as a decimal number, e.g. 129.99. Do not include currency symbols.")
    var amount: Double?

    @Guide(description: "The ISO 4217 currency code, e.g. SGD, USD, MYR.")
    var currency: String?

    @Guide(description: "A category for the product: one of Electronics, Appliance, Kitchen, Furniture, Clothing, Sports, Health, Home, Other.")
    var category: String?

    @Guide(description: "Warranty duration in months if mentioned on the receipt or warranty card, e.g. 12 or 24. Null if not found.")
    var warrantyDurationMonths: Int?
}
#endif

// MARK: - Extraction protocol & implementations

/// Protocol for extracting structured fields from raw OCR text.
protocol FieldExtractionService: Sendable {
    func extract(from ocrText: String) async -> StructuredExtractionResult
}

// MARK: - Foundation Model extraction service

/// Uses Apple's on-device Foundation Models (iOS 26+) to extract structured receipt fields.
///
/// The service:
/// 1. Checks model availability at runtime.
/// 2. Sends the OCR text with a system prompt to the on-device model.
/// 3. Requests structured `ReceiptExtractionSchema` output.
/// 4. Falls back to `.empty` if the model is unavailable or fails.
struct FoundationModelExtractionService: FieldExtractionService {

    func extract(from ocrText: String) async -> StructuredExtractionResult {
        #if canImport(FoundationModels)
        // Check if the on-device model is available.
        // The model may be unavailable if Apple Intelligence is disabled,
        // the device doesn't support it, or the model asset hasn't downloaded.
        guard SystemLanguageModel.default.availability == .available else {
            return .empty
        }

        do {
            let session = LanguageModelSession(
                instructions: """
                You are a receipt and warranty document parser. Extract structured fields from the OCR text below. \
                Be precise: prefer exact values from the text over guesses. \
                If a field is not clearly present, leave it null. \
                For dates, prefer DD/MM/YYYY (day-first) interpretation common in Singapore and APAC.
                """
            )

            // respond(to:generating:) returns a Response<T> wrapper;
            // extract the generated schema via .content.
            let response = try await session.respond(
                to: ocrText,
                generating: ReceiptExtractionSchema.self
            )

            return mapSchemaToResult(response.content)
        } catch {
            // Model failed — caller will fall back to heuristics.
            return .empty
        }
        #else
        // FoundationModels not available on this SDK — return empty.
        return .empty
        #endif
    }

    #if canImport(FoundationModels)
    private func mapSchemaToResult(_ schema: ReceiptExtractionSchema) -> StructuredExtractionResult {
        let parsedDate: Date? = {
            guard let dateStr = schema.purchaseDate else { return nil }

            // Try ISO 8601 first
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withFullDate]
            if let d = isoFormatter.date(from: dateStr) { return d }

            // Fallback: try common formats the model might produce
            let fallbackFormats = ["yyyy-MM-dd", "dd/MM/yyyy", "dd-MM-yyyy", "MM/dd/yyyy"]
            for fmt in fallbackFormats {
                let f = DateFormatter()
                f.dateFormat = fmt
                f.locale = Locale(identifier: "en_SG")
                if let d = f.date(from: dateStr) { return d }
            }
            return nil
        }()

        let documentKind: ExtractedField<DocumentKind> = {
            guard let kindStr = schema.documentKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                return .absent
            }
            // Map the model's string output to our enum, handling common variations.
            let kindMap: [String: DocumentKind] = [
                "receipt": .receipt,
                "invoice": .invoice,
                "warranty_card": .warrantyCard,
                "warranty card": .warrantyCard,
                "warrantycard": .warrantyCard,
                "order_confirmation": .orderConfirmation,
                "order confirmation": .orderConfirmation,
                "orderconfirmation": .orderConfirmation,
                "packing_slip": .packingSlip,
                "packing slip": .packingSlip,
                "packingslip": .packingSlip,
                "support_document": .supportDocument,
                "support document": .supportDocument,
                "supportdocument": .supportDocument,
                "manual": .manual,
                "unknown": .unknown,
            ]
            if let kind = kindMap[kindStr] {
                return ExtractedField(value: kind, confidence: .high)
            }
            return ExtractedField(value: .unknown, confidence: .low)
        }()

        return StructuredExtractionResult(
            documentKind: documentKind,
            productName: field(schema.productName, minLength: 2),
            merchantName: field(schema.merchantName, minLength: 2),
            purchaseDate: ExtractedField(
                value: parsedDate,
                confidence: parsedDate != nil ? .high : .none
            ),
            amount: ExtractedField(
                value: schema.amount,
                confidence: schema.amount != nil ? .high : .none
            ),
            currency: field(schema.currency, minLength: 3),
            category: field(schema.category, minLength: 2),
            warrantyDurationMonths: ExtractedField(
                value: schema.warrantyDurationMonths,
                confidence: schema.warrantyDurationMonths != nil ? .medium : .none
            ),
            source: .foundationModel
        )
    }

    /// Helper to create a string field with basic validation.
    private func field(_ value: String?, minLength: Int) -> ExtractedField<String> {
        guard let value, value.trimmingCharacters(in: .whitespacesAndNewlines).count >= minLength else {
            return .absent
        }
        return ExtractedField(value: value.trimmingCharacters(in: .whitespacesAndNewlines), confidence: .high)
    }
    #endif
}

// MARK: - Heuristic extraction service (wraps existing logic)

/// Wraps the existing VisionOCRService heuristic extraction into the `FieldExtractionService` protocol.
/// This is the fallback when Foundation Models are unavailable.
struct HeuristicExtractionService: FieldExtractionService {
    func extract(from ocrText: String) async -> StructuredExtractionResult {
        // Delegate to the same heuristic logic that VisionOCRService already uses.
        let heuristic = HeuristicFieldExtractor()
        return heuristic.extract(from: ocrText)
    }
}

/// Encapsulates the regex/heuristic field extraction logic previously embedded in VisionOCRService.
/// Pulled out so it can serve as a standalone fallback.
struct HeuristicFieldExtractor {

    func extract(from text: String) -> StructuredExtractionResult {
        StructuredExtractionResult(
            documentKind: classifyDocument(from: text),
            productName: ExtractedField(value: extractProductName(from: text), confidence: .heuristic),
            merchantName: ExtractedField(value: extractMerchantName(from: text), confidence: .heuristic),
            purchaseDate: ExtractedField(value: extractDate(from: text), confidence: .heuristic),
            amount: ExtractedField(value: extractAmount(from: text), confidence: .heuristic),
            currency: ExtractedField(value: extractCurrency(from: text), confidence: .heuristic),
            category: .absent,
            warrantyDurationMonths: .absent,
            source: .heuristic
        )
    }

    // MARK: - Document classification

    private func classifyDocument(from text: String) -> ExtractedField<DocumentKind> {
        let lower = text.lowercased()

        // Score each kind by keyword presence.
        let scores: [(DocumentKind, Int)] = [
            (.receipt, countKeywords(lower, ["receipt", "change due", "subtotal", "cashier", "payment method"])),
            (.invoice, countKeywords(lower, ["invoice", "bill to", "due date", "payment terms", "invoice no", "invoice number"])),
            (.warrantyCard, countKeywords(lower, ["warranty", "guarantee", "coverage", "warranty card", "warranty period"])),
            (.orderConfirmation, countKeywords(lower, ["order confirmation", "order number", "order #", "your order", "shipping to"])),
            (.packingSlip, countKeywords(lower, ["packing slip", "packing list", "shipped", "qty shipped", "items shipped"])),
            (.supportDocument, countKeywords(lower, ["support", "service request", "case number", "ticket", "rma"])),
            (.manual, countKeywords(lower, ["user manual", "instructions", "getting started", "safety information", "table of contents"])),
        ]

        let best = scores.max(by: { $0.1 < $1.1 })
        if let best, best.1 >= 2 {
            return ExtractedField(value: best.0, confidence: .heuristic)
        } else if let best, best.1 == 1 {
            return ExtractedField(value: best.0, confidence: .low)
        }
        return ExtractedField(value: .unknown, confidence: .low)
    }

    private func countKeywords(_ text: String, _ keywords: [String]) -> Int {
        keywords.filter { text.contains($0) }.count
    }

    // MARK: - Field extraction heuristics (migrated from VisionOCRService)

    private func extractProductName(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !looksLikeDate($0) && !looksLikeTotal($0) && !looksLikeAddress($0) && !looksLikeHeader($0) }
            .filter { $0.count >= 4 && $0.count <= 80 }

        let candidates = lines.dropFirst()
        return candidates.max(by: { $0.count < $1.count })
    }

    private func extractMerchantName(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count >= 3 }

        for line in lines.prefix(5) {
            if !looksLikeDate(line) && !looksLikePureNumber(line) && line.count >= 3 {
                return line
            }
        }
        return lines.first
    }

    private func extractDate(from text: String) -> Date? {
        let sgPatterns = [
            #"(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{4})"#,
            #"(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{2})"#,
        ]

        for pattern in sgPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {

                let dayStr = String(text[Range(match.range(at: 1), in: text)!])
                let monthStr = String(text[Range(match.range(at: 2), in: text)!])
                var yearStr = String(text[Range(match.range(at: 3), in: text)!])

                if yearStr.count == 2 { yearStr = "20" + yearStr }

                if let day = Int(dayStr), let month = Int(monthStr), let year = Int(yearStr),
                   day >= 1, day <= 31, month >= 1, month <= 12, year >= 2000, year <= 2099 {
                    var components = DateComponents()
                    components.day = day
                    components.month = month
                    components.year = year
                    if let date = Calendar.current.date(from: components) { return date }
                }
            }
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        return matches.first?.date
    }

    private func extractAmount(from text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)

        for line in lines.reversed() {
            let lower = line.lowercased()
            if lower.contains("total") || lower.contains("amount") || lower.contains("grand total") || lower.contains("nett") {
                if let amount = extractNumber(from: line) { return amount }
            }
        }

        var amounts: [Double] = []
        let amountPattern = #"(?:\$|SGD|S\$|MYR|RM)\s*(\d{1,}[,.]?\d{0,2})"#
        if let regex = try? NSRegularExpression(pattern: amountPattern, options: .caseInsensitive) {
            let fullText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: fullText.length))
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    let numStr = String(text[range]).replacingOccurrences(of: ",", with: "")
                    if let num = Double(numStr) { amounts.append(num) }
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
        if lower.contains("$") { return "SGD" }
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
