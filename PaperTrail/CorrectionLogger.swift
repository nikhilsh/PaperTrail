import Foundation
import OSLog

/// Logs corrections when a user changes an extracted field value before saving.
///
/// Each correction captures the original extracted value, what the user changed it to,
/// the field name, extraction source, confidence level, and document kind.
/// This data enables future analysis of extraction accuracy without any ML overhead —
/// just structured local logging.
///
/// Corrections are appended to a JSON Lines file in the app's documents directory
/// and also emitted to os_log for real-time debugging.
enum CorrectionLogger {
    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "corrections")

    /// A single correction event.
    struct CorrectionEntry: Codable, Sendable {
        let timestamp: Date
        let fieldName: String
        let originalValue: String
        let correctedValue: String
        let source: String       // ExtractionSource raw value
        let confidence: String   // ExtractionConfidence raw value
        let documentKind: String // DocumentKind raw value
    }

    /// Compare original extraction values to the user's final values and log any differences.
    ///
    /// Call this from DraftRecordView's save flow, passing the structured extraction result
    /// and the user's final field values.
    static func logCorrections(
        structured: StructuredExtractionResult?,
        documentKind: DocumentKind?,
        finalProductName: String,
        finalMerchantName: String,
        finalPurchaseDate: Date,
        finalAmount: Double?,
        finalCurrency: String,
        finalCategory: String,
        finalWarrantyMonths: Int?
    ) {
        guard let structured else { return }

        let kind = (documentKind ?? structured.documentKind.value ?? .unknown).rawValue
        var corrections: [CorrectionEntry] = []

        // Product name
        if let original = structured.productName.value,
           !original.isEmpty,
           original != finalProductName,
           !finalProductName.isEmpty {
            corrections.append(CorrectionEntry(
                timestamp: .now,
                fieldName: "productName",
                originalValue: original,
                correctedValue: finalProductName,
                source: structured.source.rawValue,
                confidence: structured.productName.confidence.rawValue,
                documentKind: kind
            ))
        }

        // Merchant name
        if let original = structured.merchantName.value,
           !original.isEmpty,
           original != finalMerchantName,
           !finalMerchantName.isEmpty {
            corrections.append(CorrectionEntry(
                timestamp: .now,
                fieldName: "merchantName",
                originalValue: original,
                correctedValue: finalMerchantName,
                source: structured.source.rawValue,
                confidence: structured.merchantName.confidence.rawValue,
                documentKind: kind
            ))
        }

        // Purchase date
        if let original = structured.purchaseDate.value {
            let calendar = Calendar.current
            if !calendar.isDate(original, inSameDayAs: finalPurchaseDate) {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withFullDate]
                corrections.append(CorrectionEntry(
                    timestamp: .now,
                    fieldName: "purchaseDate",
                    originalValue: fmt.string(from: original),
                    correctedValue: fmt.string(from: finalPurchaseDate),
                    source: structured.source.rawValue,
                    confidence: structured.purchaseDate.confidence.rawValue,
                    documentKind: kind
                ))
            }
        }

        // Amount
        if let original = structured.amount.value, let finalAmt = finalAmount, abs(original - finalAmt) > 0.01 {
            corrections.append(CorrectionEntry(
                timestamp: .now,
                fieldName: "amount",
                originalValue: String(format: "%.2f", original),
                correctedValue: String(format: "%.2f", finalAmt),
                source: structured.source.rawValue,
                confidence: structured.amount.confidence.rawValue,
                documentKind: kind
            ))
        }

        // Currency
        if let original = structured.currency.value,
           !original.isEmpty,
           original != finalCurrency {
            corrections.append(CorrectionEntry(
                timestamp: .now,
                fieldName: "currency",
                originalValue: original,
                correctedValue: finalCurrency,
                source: structured.source.rawValue,
                confidence: structured.currency.confidence.rawValue,
                documentKind: kind
            ))
        }

        // Category
        if let original = structured.category.value,
           !original.isEmpty,
           original != finalCategory,
           !finalCategory.isEmpty {
            corrections.append(CorrectionEntry(
                timestamp: .now,
                fieldName: "category",
                originalValue: original,
                correctedValue: finalCategory,
                source: structured.source.rawValue,
                confidence: structured.category.confidence.rawValue,
                documentKind: kind
            ))
        }

        // Warranty duration months
        if let original = structured.warrantyDurationMonths.value,
           let finalMonths = finalWarrantyMonths,
           original != finalMonths {
            corrections.append(CorrectionEntry(
                timestamp: .now,
                fieldName: "warrantyDurationMonths",
                originalValue: "\(original)",
                correctedValue: "\(finalMonths)",
                source: structured.source.rawValue,
                confidence: structured.warrantyDurationMonths.confidence.rawValue,
                documentKind: kind
            ))
        }

        // Write corrections
        for entry in corrections {
            writeEntry(entry)
        }
    }

    // MARK: - Storage

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static var logFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("extraction_corrections.jsonl")
    }

    private static func writeEntry(_ entry: CorrectionEntry) {
        // Log to os_log for real-time debugging
        logger.info("Correction: \(entry.fieldName) '\(entry.originalValue)' → '\(entry.correctedValue)' [\(entry.confidence)/\(entry.source)] kind=\(entry.documentKind)")

        // Append to JSONL file
        do {
            let data = try encoder.encode(entry)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")

            let url = logFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                handle.closeFile()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            logger.error("Failed to write correction log: \(error.localizedDescription)")
        }
    }

    /// Read all logged corrections (for debugging / future analytics).
    static func readAllCorrections() -> [CorrectionEntry] {
        let url = logFileURL
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return contents
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(CorrectionEntry.self, from: data)
            }
    }
}
