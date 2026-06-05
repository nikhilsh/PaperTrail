import Testing
import Foundation
import SwiftData
@testable import PaperTrail

/// Learning-loop integration: stored merchant hints now reach the heuristic
/// path (learned-product rescue, document-kind bias) instead of being FM-only.
struct LearningIntegrationTests {

    // MARK: - Hint interpretation (pure)

    @Test func hintedProductNameParsesQuotedValue() {
        let context = makeContext(productHint: "Prefer the main purchased item line similar to 'LG Washer Dryer'.")
        #expect(context.hintedProductName == "LG Washer Dryer")

        let noQuotes = makeContext(productHint: "Prefer the main purchased item.")
        #expect(noQuotes.hintedProductName == nil)

        let empty = makeContext(productHint: nil)
        #expect(empty.hintedProductName == nil)
    }

    @Test func dayFirstDateHintDetected() {
        let dayFirst = makeContext(dateHint: "This merchant commonly uses purchase dates like 17/08/2025 in day-first format.")
        #expect(dayFirst.prefersDayFirstDates)
        #expect(!makeContext(dateHint: nil).prefersDayFirstDates)
    }

    @Test func lineMatchingFindsBestTranscriptLine() {
        let text = """
        GST Reg No: M2-0116439-7
        02SKMW
        LG WASHER DRYER COMBO UNIT
        1,479.00
        """
        #expect(HeuristicFieldExtractor.lineMatching("LG Washer Dryer", in: text) == "LG WASHER DRYER COMBO UNIT")
        // Under half the words matching → no rescue.
        #expect(HeuristicFieldExtractor.lineMatching("Espresso Machine Deluxe", in: text) == nil)
    }

    // MARK: - Heuristic integration

    @Test func learnedDocumentKindBiasesAmbiguousText() {
        let ambiguous = "completely uninformative words here\nnothing else"
        let extractor = HeuristicFieldExtractor()

        let without = extractor.extract(from: ambiguous, learningContext: nil)
        #expect(without.documentKind.value == DocumentKind.unknown)

        let context = makeContext(likelyDocumentKind: .invoice, confidence: 0.5)
        let with = extractor.extract(from: ambiguous, learningContext: context)
        #expect(with.documentKind.value == DocumentKind.invoice)
        #expect(with.documentKind.confidence == .low)

        // Below the trust floor the bias must not fire.
        let weak = makeContext(likelyDocumentKind: .invoice, confidence: 0.1)
        let withWeak = extractor.extract(from: ambiguous, learningContext: weak)
        #expect(withWeak.documentKind.value == DocumentKind.unknown)
    }

    @Test func productRescuedFromMerchantHint() {
        // Column-major-style fragment: codes and prices only — nothing the
        // heuristic would normally accept as a product name except the hinted line.
        let text = """
        T0176905
        02SKMW
        LG WASHER DRYER COMBO UNIT
        1,479.00
        """
        let context = makeContext(
            productHint: "Prefer the main purchased item line similar to 'LG Washer Dryer'.",
            confidence: 0.5
        )
        let result = HeuristicFieldExtractor().extract(from: text, learningContext: context)
        #expect(result.productName.value == "LG WASHER DRYER COMBO UNIT")
    }

    // MARK: - Context construction (consistent kind only)

    @Test @MainActor func likelyKindSetOnlyWhenMerchantIsConsistent() throws {
        let schema = Schema([PurchaseRecord.self, Attachment.self, MerchantProfile.self, ProductCategoryMemory.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))

        let consistent = MerchantProfile(
            normalizedName: MerchantLearningService.normalizeMerchantName("Gain City"),
            displayName: "Gain City",
            documentKinds: [.invoice],
            correctionCount: 5
        )
        let mixed = MerchantProfile(
            normalizedName: MerchantLearningService.normalizeMerchantName("Mixed Mart"),
            displayName: "Mixed Mart",
            documentKinds: [.invoice, .receipt],
            correctionCount: 5
        )
        context.insert(consistent)
        context.insert(mixed)

        let service = MerchantLearningService(modelContext: context)

        var structured = StructuredExtractionResult.empty
        structured.merchantName = ExtractedField(value: "Gain City", confidence: .high)
        #expect(service.learningContext(for: structured)?.likelyDocumentKind == .invoice)

        var mixedStructured = StructuredExtractionResult.empty
        mixedStructured.merchantName = ExtractedField(value: "Mixed Mart", confidence: .high)
        #expect(service.learningContext(for: mixedStructured)?.likelyDocumentKind == nil)
    }

    // MARK: - Helpers

    private func makeContext(
        productHint: String? = nil,
        dateHint: String? = nil,
        likelyDocumentKind: DocumentKind? = nil,
        confidence: Double = 0.5
    ) -> MerchantLearningContext {
        MerchantLearningContext(
            profileID: UUID(),
            normalizedMerchantName: "gaincity",
            displayMerchantName: "Gain City",
            categorySuggestion: nil,
            currencySuggestion: nil,
            warrantySuggestionMonths: nil,
            amountHint: nil,
            dateHint: dateHint,
            productHint: productHint,
            likelyDocumentKind: likelyDocumentKind,
            confidence: confidence
        )
    }
}
