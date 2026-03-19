import Foundation

struct OCRExtractionResult: Hashable, Sendable {
    var recognizedText: String
    var suggestedProductName: String?
    var suggestedMerchantName: String?
    var suggestedPurchaseDate: Date?
    var suggestedAmount: Double?
    var suggestedCurrency: String?
    var suggestedNotes: String?

    static let empty = OCRExtractionResult(recognizedText: "")
}
