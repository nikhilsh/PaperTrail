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

    /// The full structured extraction result, preserved for confidence-aware UI.
    /// Only available when the extraction pipeline was used (not for manually constructed results).
    var structuredResult: StructuredExtractionResult?

    static let empty = OCRExtractionResult(recognizedText: "")
}
