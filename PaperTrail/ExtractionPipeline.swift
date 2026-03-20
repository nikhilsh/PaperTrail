import Foundation

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
struct ExtractionPipeline: Sendable {

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
            return .empty
        }

        // Run both extractions concurrently.
        async let fmResult = foundationModelService.extract(from: ocrText)
        async let heuristicResult = heuristicService.extract(from: ocrText)

        let fm = await fmResult
        let heuristic = await heuristicResult

        // If Foundation Model returned nothing useful, use heuristic directly.
        if fm.source == .none {
            return heuristic
        }

        // Merge: prefer FM values, fall back to heuristic for missing fields.
        return merge(primary: fm, fallback: heuristic)
    }

    // MARK: - Merging

    private func merge(
        primary: StructuredExtractionResult,
        fallback: StructuredExtractionResult
    ) -> StructuredExtractionResult {
        StructuredExtractionResult(
            productName: pick(primary.productName, fallback.productName),
            merchantName: pick(primary.merchantName, fallback.merchantName),
            purchaseDate: pick(primary.purchaseDate, fallback.purchaseDate),
            amount: pick(primary.amount, fallback.amount),
            currency: pick(primary.currency, fallback.currency),
            category: pick(primary.category, fallback.category),
            warrantyDurationMonths: pick(primary.warrantyDurationMonths, fallback.warrantyDurationMonths),
            source: primary.source
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
        OCRExtractionResult(
            recognizedText: recognizedText,
            suggestedProductName: productName.value,
            suggestedMerchantName: merchantName.value,
            suggestedPurchaseDate: purchaseDate.value,
            suggestedAmount: amount.value,
            suggestedCurrency: currency.value,
            suggestedCategory: category.value,
            suggestedWarrantyDurationMonths: warrantyDurationMonths.value,
            extractionSource: source,
            suggestedNotes: recognizedText.isEmpty ? nil : "Extracted from scanned document."
        )
    }
}
