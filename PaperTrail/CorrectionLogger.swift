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

    static var onLearningFeedback: ((LearningFeedbackPayload) -> Void)?

    /// A single correction event.
    struct CorrectionEntry: Codable, Sendable {
        let timestamp: Date
        let fieldName: String
        let originalValue: String
        let correctedValue: String
        let source: String       // ExtractionSource raw value
        let confidence: String   // ExtractionConfidence raw value
        let documentKind: String // DocumentKind raw value
        /// Normalized merchant key, so corrections can be replayed as per-merchant
        /// few-shot examples. Optional: pre-existing log lines decode as nil.
        var merchant: String? = nil
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
        let merchantKey: String? = {
            let normalized = MerchantLearningService.normalizeMerchantName(finalMerchantName)
            return normalized.isEmpty ? nil : normalized
        }()
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
                documentKind: kind,
                merchant: merchantKey
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
                documentKind: kind,
                merchant: merchantKey
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
                    documentKind: kind,
                    merchant: merchantKey
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
                documentKind: kind,
                merchant: merchantKey
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
                documentKind: kind,
                merchant: merchantKey
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
                documentKind: kind,
                merchant: merchantKey
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
                documentKind: kind,
                merchant: merchantKey
            ))
        }

        let payload = LearningFeedbackPayload(
            structured: structured,
            documentKind: documentKind,
            finalProductName: finalProductName,
            finalMerchantName: finalMerchantName,
            finalPurchaseDate: finalPurchaseDate,
            finalAmount: finalAmount,
            finalCurrency: finalCurrency,
            finalCategory: finalCategory,
            finalWarrantyMonths: finalWarrantyMonths
        )

        onLearningFeedback?(payload)

        // Write corrections
        for entry in corrections {
            writeEntry(entry, to: logFileURL)
        }

        // Community learning (opt-in, anonymized): drain everything logged
        // locally that hasn't been uploaded yet. No-op when unconfigured or
        // not opted in — the local JSONL keeps queueing either way.
        CommunityLearning.shared.scheduleSync()
    }

    // MARK: - Confirmations (device → community only)

    /// Log "extraction got it right" events for the community-aggregated
    /// fields. Confirmations are majority-vote signal exactly like corrections
    /// (`mode()` over corrected_value doesn't care that original == corrected)
    /// and fire on nearly every save, so the ≥3-install bar is reachable with
    /// a small user base. Kept in their OWN file: they must never pollute
    /// few-shot prompts or the Diagnostics correction counts.
    static func logConfirmations(
        structured: StructuredExtractionResult?,
        finalMerchantName: String,
        finalCurrency: String,
        finalCategory: String
    ) {
        let entries = confirmationEntries(
            structured: structured,
            finalMerchantName: finalMerchantName,
            finalCurrency: finalCurrency,
            finalCategory: finalCategory
        )
        for entry in entries {
            writeEntry(entry, to: confirmationsFileURL, alsoOSLog: false)
        }
    }

    /// Pure builder — unit-tested directly. A field is confirmed when
    /// extraction produced a non-empty value and the user kept it verbatim.
    static func confirmationEntries(
        structured: StructuredExtractionResult?,
        finalMerchantName: String,
        finalCurrency: String,
        finalCategory: String,
        now: Date = .now
    ) -> [CorrectionEntry] {
        guard let structured else { return [] }
        let merchantKey = MerchantLearningService.normalizeMerchantName(finalMerchantName)
        guard !merchantKey.isEmpty else { return [] }
        let kind = (structured.documentKind.value ?? .unknown).rawValue

        var entries: [CorrectionEntry] = []
        func confirm(_ fieldName: String, extracted: String?, final: String, confidence: String) {
            guard let extracted, !extracted.isEmpty, extracted == final else { return }
            entries.append(CorrectionEntry(
                timestamp: now,
                fieldName: fieldName,
                originalValue: extracted,
                correctedValue: extracted,
                source: "confirmed-" + structured.source.rawValue,
                confidence: confidence,
                documentKind: kind,
                merchant: merchantKey
            ))
        }
        confirm("merchantName", extracted: structured.merchantName.value, final: finalMerchantName,
                confidence: structured.merchantName.confidence.rawValue)
        confirm("currency", extracted: structured.currency.value, final: finalCurrency,
                confidence: structured.currency.confidence.rawValue)
        confirm("category", extracted: structured.category.value, final: finalCategory,
                confidence: structured.category.confidence.rawValue)
        return entries
    }

    // MARK: - Post-save edits

    /// The community-relevant field values of a record before an edit —
    /// captured by EditRecordView before it mutates the record.
    struct RecordSnapshot: Sendable {
        var productName: String
        var merchantName: String
        var purchaseDate: Date
        var amount: Double?
        var currency: String
        var category: String
    }

    /// Log corrections made AFTER the initial save (Edit Record). The original
    /// extraction is long gone, so source/confidence say so — but "the value I
    /// first accepted was wrong" is the same majority-vote signal, and this is
    /// where many real-world fixes actually happen.
    static func logPostSaveEdits(before: RecordSnapshot, after: RecordSnapshot) {
        let entries = postSaveEditEntries(before: before, after: after)
        guard !entries.isEmpty else { return }
        for entry in entries {
            writeEntry(entry, to: logFileURL)
        }
        CommunityLearning.shared.scheduleSync()
    }

    /// Pure builder — unit-tested directly. Mirrors `logCorrections`' rules:
    /// non-empty → different non-empty only, same-day dates and sub-cent
    /// amount changes don't count.
    static func postSaveEditEntries(
        before: RecordSnapshot,
        after: RecordSnapshot,
        now: Date = .now
    ) -> [CorrectionEntry] {
        let merchantKey: String? = {
            let normalized = MerchantLearningService.normalizeMerchantName(after.merchantName)
            return normalized.isEmpty ? nil : normalized
        }()
        var entries: [CorrectionEntry] = []
        func edited(_ fieldName: String, original: String, corrected: String) {
            guard !original.isEmpty, !corrected.isEmpty, original != corrected else { return }
            entries.append(CorrectionEntry(
                timestamp: now,
                fieldName: fieldName,
                originalValue: original,
                correctedValue: corrected,
                source: "postSaveEdit",
                confidence: "unknown",
                documentKind: "unknown",
                merchant: merchantKey
            ))
        }
        edited("productName", original: before.productName, corrected: after.productName)
        edited("merchantName", original: before.merchantName, corrected: after.merchantName)
        edited("currency", original: before.currency, corrected: after.currency)
        edited("category", original: before.category, corrected: after.category)
        if !Calendar.current.isDate(before.purchaseDate, inSameDayAs: after.purchaseDate) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withFullDate]
            edited("purchaseDate", original: fmt.string(from: before.purchaseDate), corrected: fmt.string(from: after.purchaseDate))
        }
        if let old = before.amount, let new = after.amount, abs(old - new) > 0.01 {
            edited("amount", original: String(format: "%.2f", old), corrected: String(format: "%.2f", new))
        }
        return entries
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

    private static var confirmationsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("extraction_confirmations.jsonl")
    }

    private static func writeEntry(_ entry: CorrectionEntry, to url: URL, alsoOSLog: Bool = true) {
        // Log to os_log for real-time debugging
        if alsoOSLog {
            logger.info("Correction: \(entry.fieldName) '\(entry.originalValue)' → '\(entry.correctedValue)' [\(entry.confidence)/\(entry.source)] kind=\(entry.documentKind)")
        }

        // Append to JSONL file
        do {
            let data = try encoder.encode(entry)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")

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

    /// Aggregate, non-PII view of the corrections log — counts only, never
    /// values — for the Diagnostics screen and the Copy-diagnostics blob.
    /// This is the first consumer of the previously write-only JSONL.
    struct CorrectionHealth: Sendable {
        var totalCorrections = 0
        var last30Days = 0
        var byField: [String: Int] = [:]
        var bySource: [String: Int] = [:]

        /// The field users fix most — the next place extraction should improve.
        /// Ties break alphabetically so the answer is deterministic.
        var mostCorrectedField: String? {
            byField.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.first?.key
        }
    }

    /// Summarize the corrections log. `entries` is injectable for tests;
    /// defaults to reading the on-disk JSONL.
    static func healthSummary(now: Date = .now, entries: [CorrectionEntry]? = nil) -> CorrectionHealth {
        var health = CorrectionHealth()
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        for entry in entries ?? readAllCorrections() {
            health.totalCorrections += 1
            if entry.timestamp >= cutoff { health.last30Days += 1 }
            health.byField[entry.fieldName, default: 0] += 1
            health.bySource[entry.source, default: 0] += 1
        }
        return health
    }

    /// Up to `limit` recent corrections for one merchant, formatted as few-shot
    /// prompt lines — the strongest adaptation available without touching model
    /// weights. Values are truncated and the count hard-capped to protect the
    /// FM context window (it has overflowed before); everything stays on-device.
    static func fewShotExamples(
        forNormalizedMerchant merchant: String?,
        limit: Int = 2,
        entries: [CorrectionEntry]? = nil
    ) -> [String] {
        guard let merchant, !merchant.isEmpty else { return [] }
        let relevant = (entries ?? readAllCorrections()).filter { $0.merchant == merchant }
        return relevant.suffix(limit).map { entry in
            "On a previous document from this merchant, '\(clip(entry.originalValue))' was the wrong \(entry.fieldName); the correct value was '\(clip(entry.correctedValue))'."
        }
    }

    private static func clip(_ value: String, max: Int = 60) -> String {
        value.count <= max ? value : String(value.prefix(max)) + "…"
    }

    /// Read all logged corrections (for debugging / future analytics).
    static func readAllCorrections() -> [CorrectionEntry] {
        readEntries(from: logFileURL)
    }

    /// Read all logged confirmations (community upload queue only).
    static func readAllConfirmations() -> [CorrectionEntry] {
        readEntries(from: confirmationsFileURL)
    }

    private static func readEntries(from url: URL) -> [CorrectionEntry] {
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
