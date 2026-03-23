import Foundation
import OSLog
import UIKit
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
/// 2. Cleans OCR text to remove junk that triggers locale detection errors.
/// 3. Sends the cleaned text with a system prompt to the on-device model.
/// 4. Retries with progressively more aggressive filtering on locale errors.
/// 5. Falls back to `.empty` if the model is unavailable or all attempts fail.
struct FoundationModelExtractionService: FieldExtractionService {

    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "extraction.fm")

    // MARK: - OCR text cleaning

    /// Cleans raw OCR text to remove junk lines that may trigger the on-device model's
    /// language detection (causing "unsupported language or locale" errors).
    ///
    /// - Parameter text: Raw OCR text from Vision.
    /// - Parameter aggressive: If true, applies stricter filtering (removes more lines).
    /// - Parameter maxLength: Maximum character count for the returned string.
    /// - Returns: Cleaned text with an English context prefix.
    private func cleanOCRTextForModel(_ text: String, aggressive: Bool = false, maxLength: Int = 3000) -> String {
        let lines = text.components(separatedBy: .newlines)

        let filtered = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Remove empty lines
            guard !trimmed.isEmpty else { return nil }

            // Remove lines shorter than 3 characters (OCR fragments like "(C", "rm")
            guard trimmed.count >= 3 else { return nil }

            // Remove lines that are purely numeric, dates, or punctuation
            let stripped = trimmed.replacingOccurrences(of: " ", with: "")
            if stripped.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," || $0 == "-" || $0 == "/" || $0 == ":" }) {
                return nil
            }

            // Remove lines that look like page headers
            let lower = trimmed.lowercased()
            if lower.hasPrefix("page ") || lower.contains("1 of 1") || lower.contains("print date") {
                return nil
            }

            // In aggressive mode, apply stricter filters
            if aggressive {
                // Remove lines shorter than 5 characters
                guard trimmed.count >= 5 else { return nil }

                // Remove lines with fewer than 2 letter characters (likely codes/junk)
                let letterCount = trimmed.filter { $0.isLetter }.count
                guard letterCount >= 2 else { return nil }

                // Remove lines that are mostly non-ASCII (potential non-English trigger)
                let asciiCount = trimmed.unicodeScalars.filter { $0.isASCII }.count
                guard asciiCount > trimmed.count / 2 else { return nil }

                // Remove lines that start with punctuation/special chars (OCR fragments)
                if let first = trimmed.first, !first.isLetter && !first.isNumber {
                    return nil
                }

                // Remove lines with very low English word ratio
                let words = trimmed.split(separator: " ")
                if words.count >= 2 {
                    let englishishWords = words.filter { word in
                        let w = String(word).lowercased()
                        // A word is "English-ish" if it's alphabetic and >= 2 chars
                        return w.count >= 2 && w.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" })
                    }
                    if englishishWords.count == 0 { return nil }
                }
            } else {
                // Standard mode: remove lines that start with unmatched parenthesis (OCR fragment)
                if trimmed.hasPrefix("(") && trimmed.count < 6 && !trimmed.contains(")") {
                    return nil
                }

                // Remove lines that are clearly junk fragments (< 3 letter chars)
                let letterCount = trimmed.filter { $0.isLetter }.count
                if letterCount < 2 { return nil }
            }

            return trimmed
        }

        // Join and truncate
        var cleaned = filtered.joined(separator: "\n")
        if cleaned.count > maxLength {
            // Truncate at a line boundary
            let truncated = String(cleaned.prefix(maxLength))
            if let lastNewline = truncated.lastIndex(of: "\n") {
                cleaned = String(truncated[..<lastNewline])
            } else {
                cleaned = truncated
            }
        }

        // Prepend English context to anchor the model's language detection
        let prefix = "The following is OCR text from a purchase receipt or order document:\n\n"
        return prefix + cleaned
    }

    /// Checks whether an error is a locale/language-related Foundation Models error.
    private func isLocaleError(_ error: Error) -> Bool {
        let desc = error.localizedDescription.lowercased()
        return desc.contains("locale") || desc.contains("language") || desc.contains("unsupported")
    }

    func extract(from ocrText: String) async -> StructuredExtractionResult {
        #if canImport(FoundationModels)
        let availability = SystemLanguageModel.default.availability
        let rawAvailability = String(describing: availability)

        // Always log the raw availability value for diagnostics
        Self.logger.info("Foundation Models raw availability: \(rawAvailability, privacy: .public)")

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
                // Capture ALL non-.available states with their raw description
                reason = "non-available state: \(rawAvailability)"
            }
            Self.logger.warning("Foundation Models unavailable: \(reason, privacy: .public) [raw: \(rawAvailability, privacy: .public)]")

            // Send Sentry event for devices that should support FM
            let deviceModel = UIDevice.current.model // e.g. "iPhone"
            let deviceName = Self.deviceModelIdentifier() // e.g. "iPhone17,1"
            let iosVersion = UIDevice.current.systemVersion
            AppLogger.error(
                "Foundation Models unavailable on \(deviceName) (iOS \(iosVersion)): \(reason) [raw: \(rawAvailability)]",
                category: "extraction.fm.availability",
                tags: [
                    "device_model": deviceName,
                    "device_type": deviceModel,
                    "ios_version": iosVersion,
                    "fm_availability_raw": rawAvailability,
                    "fm_reason": reason
                ]
            )

            var result = StructuredExtractionResult.empty
            result.diagnostics = ExtractionDiagnostics(
                foundationModelAvailable: false,
                foundationModelRan: false,
                foundationModelSkipReason: "\(reason) [raw: \(rawAvailability)]",
                foundationModelFieldCount: 0,
                heuristicFieldCount: 0,
                rejectedFields: []
            )
            return result
        }

        Self.logger.info("Foundation Models available — running structured extraction")

        let instructions = """
            You are a receipt and warranty document parser. Process all text in English regardless of the device locale or language settings. \
            Extract structured fields from the OCR text below. \
            Be precise: prefer exact values from the text over guesses. \
            If a field is not clearly present, leave it null. \
            Do NOT extract legal boilerplate, footer text, copyright notices, or terms & conditions as product names or merchant names. \
            For dates, prefer DD/MM/YYYY (day-first) interpretation common in Singapore and APAC. \
            Only extract dates that are clearly purchase/transaction dates — ignore copyright years, founding dates, or dates in legal text.
            """

        // Build the extraction attempts: each is (label, inputText, instructions).
        // Attempt 1: cleaned OCR text (standard filter)
        // Attempt 2: aggressively cleaned text (on locale error)
        // Attempt 3: first 500 chars of aggressively cleaned text (on locale error)
        let cleanedText = cleanOCRTextForModel(ocrText)
        let aggressiveText = cleanOCRTextForModel(ocrText, aggressive: true)
        let minimalText = cleanOCRTextForModel(ocrText, aggressive: true, maxLength: 500)

        let attempts: [(label: String, input: String)] = [
            ("attempt 1: cleaned OCR", cleanedText),
            ("attempt 2: aggressive filter", aggressiveText),
            ("attempt 3: minimal (500 chars)", minimalText),
        ]

        var lastError: Error?

        for (index, attempt) in attempts.enumerated() {
            let attemptNumber = index + 1
            Self.logger.info("FM \(attempt.label, privacy: .public) (\(attempt.input.count, privacy: .public) chars)")

            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(
                    to: attempt.input,
                    generating: ReceiptExtractionSchema.self
                )

                let schema = response.content
                let fieldCount = [
                    schema.productName, schema.merchantName, schema.purchaseDate, schema.currency, schema.category
                ].compactMap({ $0 }).count + (schema.amount != nil ? 1 : 0) + (schema.warrantyDurationMonths != nil ? 1 : 0)

                Self.logger.info("FM \(attempt.label, privacy: .public) succeeded with \(fieldCount, privacy: .public) fields")

                // Log to Sentry which attempt worked
                let skipReason: String? = attemptNumber > 1 ? "locale retry succeeded on \(attempt.label)" : nil
                if attemptNumber > 1 {
                    AppLogger.info(
                        "FM extraction succeeded on \(attempt.label) after \(attemptNumber - 1) locale error(s)",
                        category: "extraction.fm.retry"
                    )
                }

                var mapped = mapSchemaToResult(schema)
                mapped.diagnostics = ExtractionDiagnostics(
                    foundationModelAvailable: true,
                    foundationModelRan: true,
                    foundationModelSkipReason: skipReason,
                    foundationModelFieldCount: fieldCount,
                    heuristicFieldCount: 0,
                    rejectedFields: []
                )
                return mapped
            } catch {
                let errorDesc = error.localizedDescription
                Self.logger.warning("FM \(attempt.label, privacy: .public) failed: \(errorDesc, privacy: .public)")
                lastError = error

                // Only retry on locale/language errors — other errors should fail immediately
                guard isLocaleError(error) else {
                    Self.logger.error("FM non-locale error, not retrying: \(errorDesc, privacy: .public)")
                    break
                }

                // Continue to next attempt for locale errors
            }
        }

        // All attempts failed (or a non-locale error broke the loop)
        let finalErrorDesc = lastError?.localizedDescription ?? "unknown"
        Self.logger.error("Foundation Models extraction failed after all attempts: \(finalErrorDesc, privacy: .public)")

        AppLogger.error(
            "FM extraction failed after \(attempts.count) attempts: \(finalErrorDesc)",
            category: "extraction.fm.failure",
            tags: [
                "fm_error": finalErrorDesc,
                "fm_attempts": String(attempts.count),
                "fm_is_locale_error": String(lastError.map { isLocaleError($0) } ?? false)
            ]
        )

        var result = StructuredExtractionResult.empty
        result.diagnostics = ExtractionDiagnostics(
            foundationModelAvailable: true,
            foundationModelRan: false,
            foundationModelSkipReason: "error after \(attempts.count) attempts: \(finalErrorDesc)",
            foundationModelFieldCount: 0,
            heuristicFieldCount: 0,
            rejectedFields: []
        )
        return result
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

    /// Returns the hardware model identifier (e.g. "iPhone17,1") instead of the generic "iPhone" from UIDevice.
    private static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? UIDevice.current.model
            }
        }
    }
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
        let rawWarrantyMonths = extractWarrantyMonths(from: text)

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
            + (purchaseDate != nil ? 1 : 0) + (amount != nil ? 1 : 0) + (rawWarrantyMonths != nil ? 1 : 0)

        Self.logger.info("Heuristic extraction: \(fieldCount, privacy: .public) fields, \(rejected.count, privacy: .public) rejected")

        return StructuredExtractionResult(
            documentKind: docKind,
            productName: ExtractedField(value: productName, confidence: productName != nil ? .heuristic : .none),
            merchantName: ExtractedField(value: merchantName, confidence: merchantName != nil ? .heuristic : .none),
            purchaseDate: ExtractedField(value: purchaseDate, confidence: purchaseDate != nil ? .heuristic : .none),
            amount: ExtractedField(value: amount, confidence: amount != nil ? .heuristic : .none),
            currency: ExtractedField(value: rawCurrency, confidence: rawCurrency != nil ? .heuristic : .none),
            category: .absent,
            warrantyDurationMonths: ExtractedField(value: rawWarrantyMonths, confidence: rawWarrantyMonths != nil ? .heuristic : .none),
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
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Check for exact heading phrases that appear as standalone lines or prominent text.
        // These are very strong signals — a document that says "ORDER CONFIRMATION" as a heading
        // is almost certainly an order confirmation, regardless of other keyword matches.
        let headingBonus: [DocumentKind: Int] = {
            var bonus: [DocumentKind: Int] = [:]
            let headingPatterns: [(String, DocumentKind)] = [
                ("order confirmation", .orderConfirmation),
                ("invoice", .invoice),
                ("tax invoice", .invoice),
                ("warranty card", .warrantyCard),
                ("packing slip", .packingSlip),
                ("packing list", .packingSlip),
            ]
            for line in lines {
                let lineLower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                for (phrase, kind) in headingPatterns {
                    // Give a big bonus if the phrase appears as the entire line or a significant portion
                    if lineLower == phrase || (lineLower.contains(phrase) && lineLower.count < phrase.count + 15) {
                        bonus[kind, default: 0] += 3
                    }
                }
            }
            return bonus
        }()

        // Score each kind by keyword presence.
        let baseScores: [(DocumentKind, Int)] = [
            (.receipt, countKeywords(lower, ["receipt", "change due", "subtotal", "cashier", "payment method"])),
            (.invoice, countKeywords(lower, ["invoice", "bill to", "due date", "payment terms", "invoice no", "invoice number"])),
            (.warrantyCard, countKeywords(lower, ["warranty", "guarantee", "coverage", "warranty card", "warranty period"])),
            (.orderConfirmation, countKeywords(lower, ["order confirmation", "order number", "order #", "your order", "shipping to"])),
            (.packingSlip, countKeywords(lower, ["packing slip", "packing list", "shipped", "qty shipped", "items shipped"])),
            (.supportDocument, countKeywords(lower, ["support", "service request", "case number", "ticket", "rma"])),
            (.manual, countKeywords(lower, ["user manual", "instructions", "getting started", "safety information", "table of contents"])),
        ]

        // Combine base scores with heading bonuses
        let scores: [(DocumentKind, Int)] = baseScores.map { (kind, score) in
            (kind, score + (headingBonus[kind] ?? 0))
        }

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

    /// Well-known consumer electronics/appliance brands for product detection.
    private static let knownBrands: Set<String> = [
        "samsung", "apple", "sony", "lg", "dyson", "panasonic", "philips",
        "bosch", "siemens", "miele", "braun", "asus", "acer", "dell", "hp",
        "lenovo", "microsoft", "google", "bose", "jbl", "harman",
        "whirlpool", "electrolux", "hitachi", "toshiba", "sharp",
        "daikin", "mitsubishi", "fujitsu", "nikon", "canon", "olympus",
        "garmin", "fitbit", "xiaomi", "huawei", "oppo", "vivo",
        "nintendo", "playstation", "xbox", "razer", "logitech",
        "breville", "delonghi", "kitchenaid", "cuisinart", "tefal",
        "ikea", "muji", "osim", "ogawa",
    ]

    /// Extract product name with brand/model detection.
    ///
    /// Strategy:
    /// 1. Look for explicit item description patterns (model/sku/item headers).
    /// 2. Look for lines near "item"/"description"/"product" headers.
    /// 3. Scan all lines for known brand names.
    /// 4. Scan all lines for model number patterns (alphanumeric codes >= 6 chars).
    /// If a brand line is found, also check the next line for model numbers and concatenate.
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

        // Third pass: scan ALL lines for known brand names.
        // If found, also grab adjacent lines that look like model info, and concatenate.
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip very short lines, address lines, boilerplate, and total lines
            if trimmed.count < 3 || looksLikeBoilerplate(trimmed) || looksLikeAddress(trimmed) || looksLikeTotal(trimmed) {
                continue
            }

            // Check if this line contains a known brand
            let containsBrand = Self.knownBrands.contains { brand in
                // Match as whole word to avoid false positives
                let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: brand) + #"\b"#
                return lower.range(of: pattern, options: .regularExpression) != nil
            }

            if containsBrand {
                var productName = trimmed

                // Check if the next line looks like a model number — concatenate if so
                if i + 1 < lines.count {
                    let nextLine = lines[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if looksLikeModelNumber(nextLine) && !looksLikeBoilerplate(nextLine) {
                        productName = productName + " " + nextLine
                    }
                }

                // Also check if THIS line already contains a model number (common: "Samsung QA65LS03FWKXXS")
                if productName.count >= 4 && productName.count <= 120 {
                    return productName
                }
            }
        }

        // Fourth pass: scan for lines that contain model number patterns without a known brand.
        // Model numbers look like: QA65LS03FWKXXS, RT-AX88U, A2894, etc.
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < 6 || trimmed.count > 80 { continue }
            if looksLikeBoilerplate(trimmed) || looksLikeAddress(trimmed) || looksLikeTotal(trimmed) { continue }

            if looksLikeModelNumber(trimmed) {
                // Check if the previous line has a brand or descriptive text
                if i > 0 {
                    let prevLine = lines[i - 1].trimmingCharacters(in: .whitespacesAndNewlines)
                    let prevLower = prevLine.lowercased()
                    let prevHasBrand = Self.knownBrands.contains { brand in
                        prevLower.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: brand) + #"\b"#, options: .regularExpression) != nil
                    }
                    if prevHasBrand && !looksLikeBoilerplate(prevLine) {
                        return prevLine + " " + trimmed
                    }
                }
                return trimmed
            }
        }

        // Conservative: don't guess. Return nil and let the user fill it in.
        return nil
    }

    /// Checks if a string looks like a product model number.
    /// Model numbers typically contain a mix of uppercase letters and digits, total length >= 6.
    /// Examples: QA65LS03FWKXXS, RT-AX88U, WF-1000XM5
    private func looksLikeModelNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove hyphens for analysis
        let cleaned = trimmed.replacingOccurrences(of: "-", with: "")

        guard cleaned.count >= 6 else { return false }

        let hasLetters = cleaned.contains(where: { $0.isLetter })
        let hasDigits = cleaned.contains(where: { $0.isNumber })

        // Must have both letters and digits
        guard hasLetters && hasDigits else { return false }

        // Check pattern: sequence of uppercase letters + digits, or vice versa
        // Allow alphanumeric with hyphens, must be mostly alphanumeric
        let alnumCount = cleaned.filter { $0.isLetter || $0.isNumber }.count
        if alnumCount < cleaned.count * 3 / 4 { return false }

        // Should have a reasonable mix — not just "Page1" but more like "QA65LS03"
        let uppercaseLetters = cleaned.filter { $0.isUppercase }.count
        let digits = cleaned.filter { $0.isNumber }.count
        if uppercaseLetters >= 2 && digits >= 1 { return true }
        if digits >= 2 && uppercaseLetters >= 1 { return true }

        return false
    }

    /// Extract merchant name with company-pattern scanning.
    ///
    /// Strategy:
    /// 1. Scan ALL lines for company name suffixes (Pte Ltd, Inc, Corp, LLC, etc.) — very reliable signal.
    /// 2. Scan for "Store :" field and extract the store name.
    /// 3. Fall back to first 3 non-junk lines (original approach).
    /// Prefer company-suffix matches over top-of-receipt guessing.
    private func extractMerchantName(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count >= 3 }

        // Pass 1: Look for lines containing well-known company name suffixes.
        // These are extremely reliable signals for a merchant/company name.
        let companySuffixes = [
            "Pte Ltd", "Pte. Ltd", "Pte Ltd.", "Pte. Ltd.",
            "Sdn Bhd", "Sdn. Bhd", "Sdn Bhd.", "Sdn. Bhd.",
            "Inc", "Inc.", "Corp", "Corp.",
            "LLC", "L.L.C", "L.L.C.",
            "Co.", "Co.,", "& Co",
            "Ltd", "Ltd.", "Limited",
            "GmbH", "Pty Ltd", "Pty. Ltd",
        ]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for suffix in companySuffixes {
                if trimmed.localizedCaseInsensitiveContains(suffix)
                    && trimmed.count >= 8
                    && trimmed.count <= 80
                    && !looksLikeBoilerplate(trimmed)
                    && !looksLikeAddress(trimmed) {
                    // Clean up: remove registration numbers in parentheses at the end
                    let cleaned = trimmed.replacingOccurrences(
                        of: #"\s*\((?:Regn?\.?\s*No\.?|UEN|Co\.?\s*Reg).*$"#,
                        with: "",
                        options: .regularExpression
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.count >= 5 {
                        return cleaned
                    }
                    return trimmed
                }
            }
        }

        // Pass 2: Look for "Store :" or "Store:" field — common in order confirmations.
        // Parse "Store : 1004 Suntec City" → try to extract the name part after the store number.
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            // Check current line for "store" label with value on same line
            if lower.hasPrefix("store") || lower.contains("store :") || lower.contains("store:") {
                let storeLine: String
                // Handle split lines: "Store" on one line, ": value" on next
                if line.contains(":") {
                    storeLine = line
                } else if i + 1 < lines.count && lines[i + 1].hasPrefix(":") {
                    storeLine = line + " " + lines[i + 1]
                } else {
                    continue
                }
                // Extract value after the colon
                if let colonRange = storeLine.range(of: ":") {
                    let value = String(storeLine[colonRange.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.count >= 3 {
                        // Try to strip leading store number (e.g. "1004 Suntec City" → "Suntec City")
                        let stripped = value.replacingOccurrences(
                            of: #"^\d+\s+"#, with: "", options: .regularExpression
                        )
                        if stripped.count >= 3 {
                            return stripped
                        }
                        return value
                    }
                }
            }
        }

        // Pass 3: Original approach — first 3 non-junk lines.
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

    /// Extract date with keyword priority ordering.
    ///
    /// Strategy:
    /// 1. Scan ALL lines for date-related keywords with priority levels.
    /// 2. Handle OCR split-line format where label is on one line, ": value" on the next.
    /// 3. Parse dates from matched lines using explicit patterns and NSDataDetector.
    /// 4. Return the highest-priority date found.
    /// 5. Fall back to first explicit date pattern if no keyword matches.
    private func extractDate(from text: String) -> Date? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Priority levels for date-related keywords.
        // Lower number = higher priority.
        let highPriority: [(String, Int)] = [
            ("creation date", 1), ("purchase date", 1), ("transaction date", 1),
            ("date of purchase", 1), ("order date", 1),
        ]
        let mediumPriority: [(String, Int)] = [
            ("invoice date", 2), ("receipt date", 2),
        ]
        let lowPriority: [(String, Int)] = [
            ("change date", 3), ("print date", 3), ("delivery date", 3),
            ("ship date", 3), ("dispatch date", 3),
        ]
        let allKeywords = highPriority + mediumPriority + lowPriority

        // Collect date candidates with their priority.
        var candidates: [(date: Date, priority: Int)] = []

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()

            for (keyword, priority) in allKeywords {
                guard lower.contains(keyword) else { continue }

                // Skip boilerplate lines
                if looksLikeBoilerplate(line) { continue }

                // Try to extract date from this line first
                if let date = parseDateFromLine(line), isPlausibleDate(date) {
                    candidates.append((date, priority))
                    continue
                }

                // Handle split-line OCR: label on this line, ": value" on the next
                // e.g. "Creation Date" on line i, ": 15-Nov-25" on line i+1
                if i + 1 < lines.count {
                    let nextLine = lines[i + 1]
                    // Next line starts with ":" or is just a date value
                    let combined = line + " " + nextLine
                    if let date = parseDateFromLine(combined), isPlausibleDate(date) {
                        candidates.append((date, priority))
                        continue
                    }
                    // Also try just the next line in case the date is there standalone
                    if let date = parseDateFromLine(nextLine), isPlausibleDate(date) {
                        candidates.append((date, priority))
                    }
                }
            }
        }

        // Return the highest-priority candidate (lowest priority number).
        if let best = candidates.min(by: { $0.priority < $1.priority }) {
            return best.date
        }

        // Fallback: scan for lines containing generic "date" keyword (medium-ish priority).
        let genericDateKeywords = ["date", "purchase", "transaction", "order", "invoice", "receipt", "paid"]
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            let nearTransaction = genericDateKeywords.contains { lower.contains($0) }
            guard nearTransaction else { continue }
            if looksLikeBoilerplate(line) { continue }

            if let date = parseDateFromLine(line), isPlausibleDate(date) {
                return date
            }
            // Handle split lines
            if i + 1 < lines.count {
                let combined = line + " " + lines[i + 1]
                if let date = parseDateFromLine(combined), isPlausibleDate(date) {
                    return date
                }
            }
        }

        // Last resort: first explicit date pattern in entire text.
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
                    if let date = Calendar.current.date(from: components), isPlausibleDate(date) {
                        return date
                    }
                }
            }
        }

        // Conservative: don't guess.
        return nil
    }

    /// Parse a date from a single line of text, trying multiple formats.
    private func parseDateFromLine(_ line: String) -> Date? {
        // Try explicit numeric patterns first: DD/MM/YYYY, DD-MM-YYYY, etc.
        let numericPatterns = [
            #"(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{4})"#,
            #"(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{2})"#,
        ]

        for pattern in numericPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                let dayStr = String(line[Range(match.range(at: 1), in: line)!])
                let monthStr = String(line[Range(match.range(at: 2), in: line)!])
                var yearStr = String(line[Range(match.range(at: 3), in: line)!])

                if yearStr.count == 2 { yearStr = "20" + yearStr }

                if let day = Int(dayStr), let month = Int(monthStr), let year = Int(yearStr),
                   day >= 1, day <= 31, month >= 1, month <= 12, year >= 2015, year <= 2099 {
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

        // Try named month patterns: "15-Nov-25", "23 Nov 2025", "Nov 15, 2025", etc.
        let namedMonthFormats = [
            "dd-MMM-yy", "dd-MMM-yyyy",
            "dd MMM yy", "dd MMM yyyy",
            "MMM dd, yyyy", "MMM dd yyyy",
            "dd/MMM/yy", "dd/MMM/yyyy",
        ]
        for fmt in namedMonthFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = fmt
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // Try to find a date substring in the line
            // Extract potential date strings near colons or at end of line
            let searchText = line.contains(":") ?
                String(line[line.index(after: line.firstIndex(of: ":")!)...]).trimmingCharacters(in: .whitespacesAndNewlines) :
                line.trimmingCharacters(in: .whitespacesAndNewlines)

            if let date = formatter.date(from: searchText) {
                return date
            }
            // Also try the whole line
            if let date = formatter.date(from: line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return date
            }
        }

        // Fallback: NSDataDetector
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(line.startIndex..., in: line)
        let matches = detector?.matches(in: line, options: [], range: range) ?? []
        return matches.first?.date
    }

    /// Check if a date is plausible (not too old, not in the future).
    private func isPlausibleDate(_ date: Date) -> Bool {
        let year = Calendar.current.component(.year, from: date)
        return year >= 2015 && date <= Date.now.addingTimeInterval(86400)
    }

    private func extractAmount(from text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Total-related keywords in priority order (prefer "grand total" > "total" > "subtotal").
        // Lower priority number = higher preference.
        let totalKeywords: [(keyword: String, priority: Int)] = [
            ("grand total", 0),
            ("nett total", 1), ("net total", 1),
            ("total amount", 2), ("total due", 2), ("amount due", 2),
            ("total value", 3), ("balance due", 3), ("amount payable", 3),
            ("total", 4),
            ("nett", 5), ("amount", 5),
        ]

        // Pass 1: Look for lines with total keywords and extract amounts from them.
        // Also handle split lines where the keyword is on one line and the amount on the next.
        var totalAmounts: [(amount: Double, priority: Int)] = []

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()

            for (keyword, priority) in totalKeywords {
                guard lower.contains(keyword) else { continue }
                // Skip "subtotal" lines if keyword is "total" (avoid matching subtotal as total)
                if keyword == "total" && lower.contains("subtotal") { continue }

                // Try extracting from this line
                if let amount = extractDecimalAmount(from: line), amount > 0 {
                    totalAmounts.append((amount, priority))
                    break
                }

                // Handle split lines: "Total value" on one line, amounts on the following lines.
                // Scan up to 5 subsequent lines for amounts and take the LARGEST one.
                // This handles the common receipt pattern where a total keyword is followed
                // by a column of amounts (subtotals, tax, grand total).
                let maxLookahead = min(5, lines.count - i - 1)
                if maxLookahead > 0 {
                    var blockAmounts: [(amount: Double, lineOffset: Int)] = []
                    for offset in 1...maxLookahead {
                        let nextLine = lines[i + offset]
                        if let amount = extractDecimalAmount(from: nextLine), amount > 0 {
                            blockAmounts.append((amount, offset))
                        } else if !blockAmounts.isEmpty {
                            // We've passed the contiguous amount block
                            break
                        }
                    }
                    if let largest = blockAmounts.max(by: { $0.amount < $1.amount }) {
                        totalAmounts.append((largest.amount, priority))
                        break
                    }
                    // Also try combining with the immediate next line
                    let combined = line + " " + lines[i + 1]
                    if let amount = extractDecimalAmount(from: combined), amount > 0 {
                        totalAmounts.append((amount, priority))
                        break
                    }
                }
            }
        }

        // Return the best total: highest priority (lowest number), then largest amount as tiebreaker.
        // This ensures "grand total 3,180.00" beats "total 380.00", and when two keywords share
        // the same priority level, the larger amount wins (grand total > subtotal).
        if let best = totalAmounts.sorted(by: {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.amount > $1.amount  // same priority → prefer larger amount
        }).first {
            return best.amount
        }

        // Pass 2: Look for currency-prefixed amounts anywhere in the text.
        // These are amounts like "SGD 3,180.00", "$99.90", "S$1,200.00"
        var currencyAmounts: [Double] = []
        let amountPattern = #"(?:\$|SGD|S\$|MYR|RM)\s*(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)"#
        if let regex = try? NSRegularExpression(pattern: amountPattern, options: .caseInsensitive) {
            let fullText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: fullText.length))
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    let numStr = String(text[range]).replacingOccurrences(of: ",", with: "")
                    if let num = Double(numStr), num > 0 { currencyAmounts.append(num) }
                }
            }
        }

        // Return the largest currency-prefixed amount (likely the total).
        if let largest = currencyAmounts.max() {
            return largest
        }

        // Pass 3: Look for comma-thousands amounts anywhere in the text.
        // Amounts like "3,180.00" almost always represent totals or significant values —
        // small line items rarely use comma-thousands formatting.
        let commaThousandsPattern = #"(\d{1,3},\d{3}\.\d{2})"#
        var commaAmounts: [Double] = []
        if let regex = try? NSRegularExpression(pattern: commaThousandsPattern) {
            let fullText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: fullText.length))
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    let numStr = String(text[range]).replacingOccurrences(of: ",", with: "")
                    if let num = Double(numStr), num > 0 { commaAmounts.append(num) }
                }
            }
        }
        if let largest = commaAmounts.max() {
            return largest
        }

        // Pass 4: Last resort — find the single largest decimal amount anywhere in the text.
        let anyAmountPattern = #"(\d{1,3}(?:,\d{3})*\.\d{1,2}|\d+\.\d{1,2})"#
        var allAmounts: [Double] = []
        if let regex = try? NSRegularExpression(pattern: anyAmountPattern) {
            let fullText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: fullText.length))
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    let numStr = String(text[range]).replacingOccurrences(of: ",", with: "")
                    if let num = Double(numStr), num > 0 { allAmounts.append(num) }
                }
            }
        }
        return allAmounts.max()
    }

    /// Extract a decimal amount from a line, handling comma-separated thousands.
    /// Matches patterns like "3,180.00", "1200.50", "99.90", "$3,180.00", "SGD 1,200.00", etc.
    private func extractDecimalAmount(from line: String) -> Double? {
        // Match amounts with comma thousands separators and/or decimal places.
        // Ordered so comma-thousands with decimals are tried first (most specific),
        // then comma-thousands without decimals, then plain decimals.
        let pattern = #"(\d{1,3}(?:,\d{3})*\.\d{1,2}|\d{1,3}(?:,\d{3})+|\d+\.\d{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)

        // Collect all amounts on the line; return the largest.
        // This handles lines like "Subtotal 380.00 Total 3,180.00" by picking the bigger one,
        // and also handles "3,180.00" appearing after labels.
        var amounts: [Double] = []
        for match in matches {
            if let matchRange = Range(match.range(at: 1), in: line) {
                let numStr = String(line[matchRange]).replacingOccurrences(of: ",", with: "")
                if let num = Double(numStr), num > 0 {
                    amounts.append(num)
                }
            }
        }
        return amounts.max()
    }

    /// Extract warranty duration in months from text.
    /// Looks for patterns like "3 years warranty", "24 months guarantee", etc.
    private func extractWarrantyMonths(from text: String) -> Int? {
        let lower = text.lowercased()

        // Patterns where the number comes BEFORE the duration keyword
        // e.g. "3 years warranty", "24 months guarantee"
        let prefixPatterns: [(pattern: String, multiplier: Int)] = [
            (#"(\d+)\s*years?\s*(?:warranty|guarantee)"#, 12),
            (#"(\d+)\s*months?\s*(?:warranty|guarantee)"#, 1),
        ]

        // Patterns where the number comes AFTER the keyword
        // e.g. "warranty of 3 years", "warranty period: 24 months"
        let suffixPatterns: [(pattern: String, multiplier: Int)] = [
            (#"(?:warranty|guarantee)[\s\w]*?(\d+)\s*years?"#, 12),
            (#"(?:warranty|guarantee)[\s\w]*?(\d+)\s*months?"#, 1),
        ]

        let allPatterns = prefixPatterns + suffixPatterns

        for (pattern, multiplier) in allPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let numRange = Range(match.range(at: 1), in: lower),
               let months = Int(lower[numRange]) {
                let total = months * multiplier
                // Sanity check: warranty should be between 1 month and 10 years
                if total >= 1 && total <= 120 {
                    return total
                }
            }
        }

        return nil
    }

    private func extractCurrency(from text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("sgd") || lower.contains("s$") { return "SGD" }
        if lower.contains("myr") || lower.contains("rm") { return "MYR" }
        if lower.contains("usd") || lower.contains("us$") { return "USD" }
        if lower.contains("$") { return "SGD" }
        return nil
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
