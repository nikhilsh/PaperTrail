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

    static let empty = OCRExtractionResult(recognizedText: "")
}
