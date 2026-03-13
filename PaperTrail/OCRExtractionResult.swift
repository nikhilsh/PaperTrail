import Foundation

struct OCRExtractionResult: Hashable {
    var recognizedText: String
    var suggestedProductName: String?
    var suggestedMerchantName: String?
    var suggestedPurchaseDate: Date?
    var suggestedNotes: String?

    static let empty = OCRExtractionResult(recognizedText: "")
}
