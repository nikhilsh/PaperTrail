import Foundation

struct OCRExtractionResult: Hashable, Sendable {
    var recognizedText: String
    var suggestedProductName: String?
    var suggestedMerchantName: String?
    var suggestedPurchaseDate: Date?
    var suggestedAmount: Double?
    var suggestedCurrency: String?
    var suggestedCategory: String?
    var suggestedWarrantyDurationMonths: Int?
    var extractionSource: ExtractionSource?
    var suggestedNotes: String?
    var documentKind: DocumentKind?

    /// Individual line items extracted from the document.
    var lineItems: [LineItem]

    /// The full structured extraction result, preserved for confidence-aware UI.
    /// Only available when the extraction pipeline was used (not for manually constructed results).
    var structuredResult: StructuredExtractionResult?

    /// Whether Foundation Models actually ran for this extraction (vs heuristic fallback).
    var foundationModelRan: Bool {
        structuredResult?.diagnostics?.foundationModelRan ?? false
    }

    /// Human-readable description of the extraction path taken.
    var extractionPathDescription: String {
        guard let diag = structuredResult?.diagnostics else {
            return "Unknown"
        }
        if diag.foundationModelRan {
            return "Apple Intelligence (\(diag.foundationModelFieldCount) fields)"
        } else if let reason = diag.foundationModelSkipReason {
            return "Pattern matching (FM: \(reason))"
        } else {
            return "Pattern matching"
        }
    }

    static let empty = OCRExtractionResult(recognizedText: "", lineItems: [])
}
