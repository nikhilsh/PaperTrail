import Foundation
import OSLog
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
        case .heuristic: "Best guess"
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

    /// Diagnostic info about which extraction path was taken and why.
    var diagnostics: ExtractionDiagnostics?

    static let empty = StructuredExtractionResult(
        documentKind: .absent,
        productName: .absent,
        merchantName: .absent,
        purchaseDate: .absent,
        amount: .absent,
        currency: .absent,
        category: .absent,
        warrantyDurationMonths: .absent,
        source: .none,
        diagnostics: nil
    )
}

/// Diagnostic information about extraction pipeline execution.
/// Used for debugging and understanding which path was taken.
struct ExtractionDiagnostics: Sendable, Hashable {
    /// Whether Foundation Models were available on this device.
    var foundationModelAvailable: Bool
    /// Whether Foundation Models actually ran and returned a result.
    var foundationModelRan: Bool
    /// Reason Foundation Models didn't run or failed, if applicable.
    var foundationModelSkipReason: String?
    /// Number of fields the Foundation Model populated (0 if it didn't run).
    var foundationModelFieldCount: Int
    /// Number of fields the heuristic populated.
    var heuristicFieldCount: Int
    /// Which fields were rejected by quality gates.
    var rejectedFields: [String]
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

    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "extraction.fm")

    func extract(from ocrText: String) async -> StructuredExtractionResult {
        #if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability

        // Check if the on-device model is available.
        // The model may be unavailable if Apple Intelligence is disabled,
        // the device doesn't support it, or the model asset hasn't downloaded.
        guard availability == .available else {
            let reason: String
            switch availability {
            case .available:
                reason = "available" // shouldn't reach here
            case .unavailable:
                reason = "unavailable (device/region not supported)"
            default:
                reason = "unknown availability state"
            }
            Self.logger.warning("Foundation Models unavailable: \(reason, privacy: .public)")
            var result = StructuredExtractionResult.empty
            result.diagnostics = ExtractionDiagnostics(
                foundationModelAvailable: false,
                foundationModelRan: false,
                foundationModelSkipReason: reason,
                foundationModelFieldCount: 0,
                heuristicFieldCount: 0,
                rejectedFields: []
            )
            return result
        }

        Self.logger.info("Foundation Models available — running structured extraction")

        // Instructions explicitly state English to work around locale-related failures
        // ("An unsupported language or locale was used"). The model processes OCR text
        // that may originate from any locale, but our prompts and schema are English.
        let instructions = """
            You are a receipt and warranty document parser. Process all text in English regardless of the device locale or language settings. \
            Extract structured fields from the OCR text below. \
            Be precise: prefer exact values from the text over guesses. \
            If a field is not clearly present, leave it null. \
            Do NOT extract legal boilerplate, footer text, copyright notices, or terms & conditions as product names or merchant names. \
            For dates, prefer DD/MM/YYYY (day-first) interpretation common in Singapore and APAC. \
            Only extract dates that are clearly purchase/transaction dates — ignore copyright years, founding dates, or dates in legal text.
            """

        do {
            let session = LanguageModelSession(instructions: instructions)

            // respond(to:generating:) returns a Response<T> wrapper;
            // extract the generated schema via .content.
            let response = try await session.respond(
                to: ocrText,
                generating: ReceiptExtractionSchema.self
            )

            let schema = response.content
            let fieldCount = [
                schema.productName, schema.merchantName, schema.purchaseDate, schema.currency, schema.category
            ].compactMap({ $0 }).count + (schema.amount != nil ? 1 : 0) + (schema.warrantyDurationMonths != nil ? 1 : 0)

            Self.logger.info("Foundation Models returned \(fieldCount, privacy: .public) fields")

            var mapped = mapSchemaToResult(schema)
            mapped.diagnostics = ExtractionDiagnostics(
                foundationModelAvailable: true,
                foundationModelRan: true,
                foundationModelSkipReason: nil,
                foundationModelFieldCount: fieldCount,
                heuristicFieldCount: 0,
                rejectedFields: []
            )
            return mapped
        } catch {
            let errorDesc = error.localizedDescription
            let isLocaleError = errorDesc.lowercased().contains("locale")
                || errorDesc.lowercased().contains("language")
                || errorDesc.lowercased().contains("unsupported")

            // If the error looks locale-related, retry with minimal instructions.
            if isLocaleError {
                Self.logger.warning("Foundation Models locale error — retrying with simplified instructions: \(errorDesc, privacy: .public)")
                do {
                    let retrySession = LanguageModelSession(
                        instructions: "Extract receipt fields from the text. Respond in English."
                    )
                    let retryResponse = try await retrySession.respond(
                        to: ocrText,
                        generating: ReceiptExtractionSchema.self
                    )

                    let schema = retryResponse.content
                    let fieldCount = [
                        schema.productName, schema.merchantName, schema.purchaseDate, schema.currency, schema.category
                    ].compactMap({ $0 }).count + (schema.amount != nil ? 1 : 0) + (schema.warrantyDurationMonths != nil ? 1 : 0)

                    Self.logger.info("Foundation Models retry succeeded with \(fieldCount, privacy: .public) fields")

                    var mapped = mapSchemaToResult(schema)
                    mapped.diagnostics = ExtractionDiagnostics(
                        foundationModelAvailable: true,
                        foundationModelRan: true,
                        foundationModelSkipReason: "locale retry succeeded",
                        foundationModelFieldCount: fieldCount,
                        heuristicFieldCount: 0,
                        rejectedFields: []
                    )
                    return mapped
                } catch {
                    Self.logger.error("Foundation Models retry also failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            Self.logger.error("Foundation Models extraction failed: \(errorDesc, privacy: .public)")
            var result = StructuredExtractionResult.empty
            result.diagnostics = ExtractionDiagnostics(
                foundationModelAvailable: true,
                foundationModelRan: false,
                foundationModelSkipReason: "error: \(errorDesc)",
                foundationModelFieldCount: 0,
                heuristicFieldCount: 0,
                rejectedFields: []
            )
            return result
        }
        #else
        Self.logger.info("FoundationModels framework not available on this SDK")
        // FoundationModels not available on this SDK — return empty.
        var result = StructuredExtractionResult.empty
        result.diagnostics = ExtractionDiagnostics(
            foundationModelAvailable: false,
            foundationModelRan: false,
            foundationModelSkipReason: "FoundationModels framework not available (SDK)",
            foundationModelFieldCount: 0,
            heuristicFieldCount: 0,
            rejectedFields: []
        )
        return result
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
            source: .foundationModel,
            diagnostics: nil
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
///
/// IMPORTANT: Heuristics are inherently unreliable for semantic fields (product name, merchant).
/// This extractor is deliberately conservative: it prefers leaving fields blank over autofilling
/// junk from OCR boilerplate, legal text, or misidentified lines. A blank field + "needs review"
/// is always better than confidently wrong data.
struct HeuristicFieldExtractor {

    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "extraction.heuristic")

    func extract(from text: String) -> StructuredExtractionResult {
        let docKind = classifyDocument(from: text)

        let rawProduct = extractProductName(from: text)
        let rawMerchant = extractMerchantName(from: text)
        let rawDate = extractDate(from: text)
        let rawAmount = extractAmount(from: text)
        let rawCurrency = extractCurrency(from: text)

        var rejected: [String] = []

        // Apply quality gates: reject values that look like OCR junk or fail validation.
        let productName: String? = {
            guard let v = rawProduct else { return nil }
            if looksLikeBoilerplate(v) || looksLikeOCRJunk(v) {
                Self.logger.info("Rejected product name as junk/boilerplate: '\(v, privacy: .public)'")
                rejected.append("productName")
                return nil
            }
            if !isValidProductName(v) {
                Self.logger.info("Rejected product name as invalid (single word/stopword): '\(v, privacy: .public)'")
                rejected.append("productName")
                return nil
            }
            return v
        }()

        let merchantName: String? = {
            guard let v = rawMerchant else { return nil }
            if looksLikeBoilerplate(v) || looksLikeOCRJunk(v) {
                Self.logger.info("Rejected merchant name as junk/boilerplate: '\(v, privacy: .public)'")
                rejected.append("merchantName")
                return nil
            }
            if !isValidMerchantName(v) {
                Self.logger.info("Rejected merchant name as invalid (fragment/too short): '\(v, privacy: .public)'")
                rejected.append("merchantName")
                return nil
            }
            return v
        }()

        let purchaseDate: Date? = {
            guard let d = rawDate else { return nil }
            // Reject dates that are implausibly old (before 2015) or in the future.
            let year = Calendar.current.component(.year, from: d)
            if year < 2015 || d > Date.now.addingTimeInterval(86400) {
                Self.logger.info("Rejected date as implausible: year=\(year, privacy: .public)")
                rejected.append("purchaseDate")
                return nil
            }
            return d
        }()

        let amount: Double? = {
            guard let a = rawAmount else { return nil }
            // Reject amounts that are zero, negative, or implausibly large for a purchase receipt.
            if a <= 0 || a > 999_999 {
                Self.logger.info("Rejected amount as implausible: \(a, privacy: .public)")
                rejected.append("amount")
                return nil
            }
            return a
        }()

        let fieldCount = [productName, merchantName, rawCurrency].compactMap({ $0 }).count
            + (purchaseDate != nil ? 1 : 0) + (amount != nil ? 1 : 0)

        Self.logger.info("Heuristic extraction: \(fieldCount, privacy: .public) fields, \(rejected.count, privacy: .public) rejected")

        return StructuredExtractionResult(
            documentKind: docKind,
            productName: ExtractedField(value: productName, confidence: productName != nil ? .heuristic : .none),
            merchantName: ExtractedField(value: merchantName, confidence: merchantName != nil ? .heuristic : .none),
            purchaseDate: ExtractedField(value: purchaseDate, confidence: purchaseDate != nil ? .heuristic : .none),
            amount: ExtractedField(value: amount, confidence: amount != nil ? .heuristic : .none),
            currency: ExtractedField(value: rawCurrency, confidence: rawCurrency != nil ? .heuristic : .none),
            category: .absent,
            warrantyDurationMonths: .absent,
            source: .heuristic,
            diagnostics: ExtractionDiagnostics(
                foundationModelAvailable: false,
                foundationModelRan: false,
                foundationModelSkipReason: nil,
                foundationModelFieldCount: 0,
                heuristicFieldCount: fieldCount,
                rejectedFields: rejected
            )
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

    // MARK: - Boilerplate / junk detection

    /// Detects legal boilerplate, footer text, copyright notices, terms & conditions, etc.
    /// These should never be extracted as product or merchant names.
    private func looksLikeBoilerplate(_ text: String) -> Bool {
        let lower = text.lowercased()
        let boilerplateSignals = [
            "cheque", "cheques", "crossed", "non-negotiable",
            "terms and conditions", "terms & conditions", "t&c",
            "copyright", "©", "all rights reserved",
            "privacy policy", "refund policy", "return policy", "exchange policy",
            "goods sold are not", "no refund", "no exchange",
            "retain this receipt", "keep this receipt", "proof of purchase",
            "thank you for", "thanks for shopping", "visit us at",
            "member since", "loyalty", "points earned",
            "gst reg", "uen:", "co. reg", "company reg",
            "powered by", "printed by", "generated by",
            "page 1 of", "page 2 of",
            "this is not a tax invoice", "this serves as",
            "e. & o.e", "errors and omissions",
            "subject to", "governing law", "jurisdiction",
            "authorised signature", "authorized signature",
            "void if", "valid only",
        ]
        return boilerplateSignals.contains { lower.contains($0) }
    }

    // MARK: - Stopwords and validation sets

    /// Common English words that should never be extracted as product or merchant names.
    /// These appear frequently in receipts/order confirmations as status text, not product names.
    private static let stopwords: Set<String> = [
        "delivering", "delivery", "shipping", "processing", "pending",
        "confirmed", "printed", "generated", "page", "copy",
        "original", "duplicate", "payment", "status", "complete",
        "completed", "cancelled", "refunded", "shipped", "dispatched",
        "estimated", "tracking", "ordered", "received", "returned",
        "summary", "details", "information", "customer", "account",
        "address", "email", "phone", "mobile", "contact",
        "total", "subtotal", "discount", "tax", "amount",
        "quantity", "price", "item", "items", "description",
        "date", "time", "number", "order", "invoice",
        "receipt", "thank", "thanks", "welcome", "hello",
    ]

    /// Well-known short brand names that should be accepted despite being short/single-word.
    private static let knownShortBrands: Set<String> = [
        "3M", "HP", "LG", "BQ", "JBL", "UE",
        "IKEA", "Sony", "Acer", "Asus", "Dell",
        "Bose", "Dyson", "Nike", "Zara", "H&M",
        "MUJI", "Braun", "Miele", "Smeg", "Bosch",
    ]

    /// Detects OCR junk: very short fragments, lines that are mostly punctuation/symbols,
    /// parenthetical fragments, single common English words, or text that doesn't form coherent words.
    private func looksLikeOCRJunk(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Too short to be meaningful
        if trimmed.count < 3 { return true }

        // Starts or ends with unmatched parenthesis/bracket — likely a fragment
        if trimmed.hasPrefix("(") && !trimmed.contains(")") { return true }
        if trimmed.hasPrefix(")") { return true }
        if trimmed.hasPrefix("[") && !trimmed.contains("]") { return true }

        // Mostly non-alphanumeric characters (punctuation/symbols)
        let alphanumeric = trimmed.filter { $0.isLetter || $0.isNumber }
        if alphanumeric.count < trimmed.count / 2 { return true }

        // Very high ratio of uppercase + special chars — likely OCR noise or codes
        let uppercaseCount = trimmed.filter { $0.isUppercase }.count
        let letterCount = trimmed.filter { $0.isLetter }.count
        if letterCount > 0 && letterCount <= 4 && uppercaseCount == letterCount {
            // Short all-caps fragments like "COP", "GST", "QTY" — not product names
            // But allow known short brands like "IKEA", "Sony", "3M"
            if !Self.knownShortBrands.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return true
            }
        }

        // Single common English word — not a product or merchant name
        let words = trimmed.split(separator: " ")
        if words.count == 1 && Self.stopwords.contains(trimmed.lowercased()) {
            return true
        }

        return false
    }

    /// Validates a candidate product name beyond basic junk detection.
    /// Product names should be multi-word or contain model-number-like patterns.
    private func isValidProductName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(separator: " ").map(String.init)

        // Reject single-word candidates unless they look like a model number (alphanumeric mix)
        if words.count < 2 {
            // Allow model numbers like "A2894" or "RT-AX88U"
            let hasLetters = trimmed.contains(where: { $0.isLetter })
            let hasDigits = trimmed.contains(where: { $0.isNumber })
            if hasLetters && hasDigits { return true }
            // Allow known brands
            if Self.knownShortBrands.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return true
            }
            // Single generic word — reject
            return false
        }

        // Check that at least one word is NOT a stopword (i.e., contains something product-like)
        let nonStopwords = words.filter { !Self.stopwords.contains($0.lowercased()) }
        if nonStopwords.isEmpty { return false }

        return true
    }

    /// Validates a candidate merchant name beyond basic junk detection.
    /// Merchant names should not be partial-word OCR fragments.
    private func isValidMerchantName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject very short candidates — likely OCR fragments
        if trimmed.count < 5 {
            // Allow known short brands (e.g. "IKEA", "3M", "H&M")
            if Self.knownShortBrands.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return true
            }
            return false
        }

        // Reject candidates that start with a lowercase letter — likely mid-word OCR fragment
        // (e.g. "rman" from "Norman")
        if let first = trimmed.first, first.isLetter && first.isLowercase {
            return false
        }

        // Single-word candidates must be properly capitalized (first letter uppercase, >= 5 chars)
        // or contain a space (multi-word like "Harvey Norman")
        let words = trimmed.split(separator: " ")
        if words.count == 1 {
            // Single word: must start with uppercase and be >= 5 chars, or be a known brand
            guard let first = trimmed.first, first.isUppercase else { return false }
        }

        return true
    }

    // MARK: - Field extraction heuristics (migrated from VisionOCRService)

    /// Extract product name conservatively.
    ///
    /// Strategy: only return a product name if we find a line that looks like an actual
    /// product/item description (contains model numbers, brand-like words, or is in a
    /// clearly item-description context). The old approach of "longest non-filtered line"
    /// was too aggressive and would pick up legal text or footer boilerplate.
    private func extractProductName(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // First pass: look for lines that are clearly item descriptions.
        // These typically contain model numbers, SKUs, or appear near quantity/price indicators.
        let itemPatterns = [
            #"(?i)(?:model|sku|item|product|description)\s*[:#]?\s*(.+)"#,
            #"(?i)^\d+\s*x\s+(.+)"#,     // "1 x Product Name" pattern
            #"(?i)^(\d+)\s+(.{10,}?)\s+\d"#,   // qty + description + price pattern
        ]

        for pattern in itemPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let lastGroup = match.numberOfRanges - 1
                if let range = Range(match.range(at: lastGroup), in: text) {
                    let candidate = String(text[range]).trimmingCharacters(in: .whitespaces)
                    if candidate.count >= 4 && candidate.count <= 80
                        && !looksLikeBoilerplate(candidate) && !looksLikeOCRJunk(candidate) {
                        return candidate
                    }
                }
            }
        }

        // Second pass: look for lines near "order" or "item" headers.
        // Find the line after an "item"/"description"/"product" header.
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            if (lower.contains("item") || lower.contains("description") || lower.contains("product"))
                && line.count < 30 {
                // The next non-empty line might be the product
                if i + 1 < lines.count {
                    let candidate = lines[i + 1]
                    if candidate.count >= 4 && candidate.count <= 80
                        && !looksLikeBoilerplate(candidate)
                        && !looksLikeOCRJunk(candidate)
                        && !looksLikeTotal(candidate)
                        && !looksLikeAddress(candidate) {
                        return candidate
                    }
                }
            }
        }

        // Conservative: don't guess. Return nil and let the user fill it in.
        return nil
    }

    /// Extract merchant name conservatively.
    ///
    /// Strategy: only look at the first 3 lines (merchant is almost always at the top of a receipt).
    /// Apply strict filtering to avoid OCR fragments, parenthetical junk, or address lines.
    private func extractMerchantName(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count >= 3 }

        // Only check the first 3 lines — merchant name is at the top.
        for line in lines.prefix(3) {
            if !looksLikeDate(line)
                && !looksLikePureNumber(line)
                && !looksLikeAddress(line)
                && !looksLikeBoilerplate(line)
                && !looksLikeOCRJunk(line)
                && !looksLikeHeader(line)
                && line.count >= 3
                && line.count <= 60 {
                return line
            }
        }

        // Conservative: don't guess.
        return nil
    }

    /// Extract date conservatively.
    ///
    /// Strategy: prefer explicit date patterns (DD/MM/YYYY). Only use NSDataDetector
    /// for date formats near transaction-related keywords (not from random legal text).
    /// Reject dates before 2015 or in the future.
    private func extractDate(from text: String) -> Date? {
        // Pass 1: explicit date patterns (most reliable).
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
                   day >= 1, day <= 31, month >= 1, month <= 12, year >= 2015, year <= 2099 {
                    var components = DateComponents()
                    components.day = day
                    components.month = month
                    components.year = year
                    if let date = Calendar.current.date(from: components),
                       date <= Date.now.addingTimeInterval(86400) {
                        return date
                    }
                }
            }
        }

        // Pass 2: use NSDataDetector but ONLY on lines near transaction keywords.
        // This prevents picking up copyright years or dates in legal boilerplate.
        let lines = text.components(separatedBy: .newlines)
        let transactionKeywords = ["date", "purchase", "transaction", "order", "invoice", "receipt", "paid"]

        for line in lines {
            let lower = line.lowercased()
            let nearTransaction = transactionKeywords.contains { lower.contains($0) }
            guard nearTransaction else { continue }

            // Skip lines that are clearly boilerplate
            if looksLikeBoilerplate(line) { continue }

            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
            let range = NSRange(line.startIndex..., in: line)
            let matches = detector?.matches(in: line, options: [], range: range) ?? []
            if let date = matches.first?.date {
                let year = Calendar.current.component(.year, from: date)
                if year >= 2015 && date <= Date.now.addingTimeInterval(86400) {
                    return date
                }
            }
        }

        // Conservative: don't guess.
        return nil
    }

    private func extractAmount(from text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)

        // First: look for lines with "total"/"amount" keywords.
        for line in lines.reversed() {
            let lower = line.lowercased()
            if lower.contains("total") || lower.contains("amount") || lower.contains("grand total") || lower.contains("nett") {
                // Skip "subtotal" if we later find "total" — but still extract from total lines.
                if let amount = extractNumber(from: line), amount > 0 { return amount }
            }
        }

        // Second: look for currency-prefixed amounts.
        var amounts: [Double] = []
        let amountPattern = #"(?:\$|SGD|S\$|MYR|RM)\s*(\d{1,}[,.]?\d{0,2})"#
        if let regex = try? NSRegularExpression(pattern: amountPattern, options: .caseInsensitive) {
            let fullText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: fullText.length))
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    let numStr = String(text[range]).replacingOccurrences(of: ",", with: "")
                    if let num = Double(numStr), num > 0 { amounts.append(num) }
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
            || lower.contains("postal") || lower.contains("zip")
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
