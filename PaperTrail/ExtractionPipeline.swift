import Foundation
import OSLog

/// Orchestrates field extraction from OCR text.
///
/// Strategy:
/// 1. Try Apple Foundation Models (on-device LLM) for structured extraction.
/// 2. If the model is unavailable or returns insufficient fields, fall back to heuristics.
/// 3. Merge results: prefer Foundation Model values where available, fill gaps with heuristics.
///
/// This design means the app works on every iOS 26 device — even those without Apple Intelligence
/// (e.g. base-model iPhones, or regions where it isn't enabled yet) — because the heuristic
/// fallback always runs.
///
/// Key principle: **prefer blank over bad**. When only heuristics are available, high-value
/// fields (product, merchant, date) are treated with extra skepticism. A blank field that
/// the user fills in is better than confidently wrong autofill.
struct ExtractionPipeline: Sendable {

    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "extraction.pipeline")

    private let foundationModelService: FieldExtractionService
    private let heuristicService: FieldExtractionService

    init(
        foundationModelService: FieldExtractionService = FoundationModelExtractionService(),
        heuristicService: FieldExtractionService = HeuristicExtractionService()
    ) {
        self.foundationModelService = foundationModelService
        self.heuristicService = heuristicService
    }

    /// Extract structured fields from OCR text.
    ///
    /// Returns a merged result: Foundation Model values take priority, heuristic values fill gaps.
    func extract(from ocrText: String) async -> StructuredExtractionResult {
        guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Self.logger.info("Empty OCR text — skipping extraction")
            return .empty
        }

        Self.logger.info("Starting extraction pipeline (OCR text: \(ocrText.count, privacy: .public) chars)")

        // Run both extractions concurrently.
        async let fmResult = foundationModelService.extract(from: ocrText)
        async let heuristicResult = heuristicService.extract(from: ocrText)

        let fm = await fmResult
        let heuristic = await heuristicResult

        // Build combined diagnostics.
        let fmDiag = fm.diagnostics
        let hDiag = heuristic.diagnostics

        let combinedDiag = ExtractionDiagnostics(
            foundationModelAvailable: fmDiag?.foundationModelAvailable ?? false,
            foundationModelRan: fmDiag?.foundationModelRan ?? false,
            foundationModelSkipReason: fmDiag?.foundationModelSkipReason,
            foundationModelFieldCount: fmDiag?.foundationModelFieldCount ?? 0,
            heuristicFieldCount: hDiag?.heuristicFieldCount ?? 0,
            rejectedFields: hDiag?.rejectedFields ?? []
        )

        // If Foundation Model returned nothing useful, use heuristic directly.
        if fm.source == .none {
            Self.logger.info("Foundation Models returned empty — using heuristic-only result (fields: \(combinedDiag.heuristicFieldCount, privacy: .public), rejected: \(combinedDiag.rejectedFields.joined(separator: ","), privacy: .public))")
            var result = heuristic
            result.diagnostics = combinedDiag
            return result
        }

        Self.logger.info("Merging FM (\(combinedDiag.foundationModelFieldCount, privacy: .public) fields) + heuristic (\(combinedDiag.heuristicFieldCount, privacy: .public) fields)")

        // Merge: prefer FM values, fall back to heuristic for missing fields.
        var merged = merge(primary: fm, fallback: heuristic)
        merged.diagnostics = combinedDiag
        return merged
    }

    // MARK: - Merging

    private func merge(
        primary: StructuredExtractionResult,
        fallback: StructuredExtractionResult
    ) -> StructuredExtractionResult {
        StructuredExtractionResult(
            documentKind: pick(primary.documentKind, fallback.documentKind),
            productName: pick(primary.productName, fallback.productName),
            merchantName: pick(primary.merchantName, fallback.merchantName),
            purchaseDate: pick(primary.purchaseDate, fallback.purchaseDate),
            amount: pick(primary.amount, fallback.amount),
            currency: pick(primary.currency, fallback.currency),
            category: pick(primary.category, fallback.category),
            warrantyDurationMonths: pick(primary.warrantyDurationMonths, fallback.warrantyDurationMonths),
            source: primary.source,
            diagnostics: primary.diagnostics
        )
    }

    /// Pick the primary field if it has a value; otherwise use the fallback.
    private func pick<T>(_ primary: ExtractedField<T>, _ fallback: ExtractedField<T>) -> ExtractedField<T> {
        if primary.value != nil {
            return primary
        }
        return fallback
    }
}

// MARK: - Convenience bridge to OCRExtractionResult

extension StructuredExtractionResult {
    /// Convert to the existing `OCRExtractionResult` format used by the rest of the app.
    ///
    /// This bridge allows the new extraction pipeline to integrate without changing
    /// every downstream consumer at once. Over time, views can adopt `StructuredExtractionResult`
    /// directly to show per-field confidence.
    func toOCRExtractionResult(recognizedText: String) -> OCRExtractionResult {
        return OCRExtractionResult(
            recognizedText: recognizedText,
            suggestedProductName: productName.value,
            suggestedMerchantName: merchantName.value,
            suggestedPurchaseDate: purchaseDate.value,
            suggestedAmount: amount.value,
            suggestedCurrency: currency.value,
            suggestedCategory: category.value,
            suggestedWarrantyDurationMonths: warrantyDurationMonths.value,
            extractionSource: source,
            suggestedNotes: recognizedText.isEmpty ? nil : "Extracted from scanned document.",
            documentKind: documentKind.value,
            structuredResult: self
        )
    }
}
