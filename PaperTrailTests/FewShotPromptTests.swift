import Testing
import Foundation
@testable import PaperTrail

/// Per-merchant few-shot prompting (roadmap #5): the user's own corrections
/// become worked examples in the FM prompt — capped and truncated to protect
/// the context window, filtered strictly to the matched merchant.
struct FewShotPromptTests {

    private func entry(field: String, original: String, corrected: String,
                       merchant: String?, daysAgo: Double = 1) -> CorrectionLogger.CorrectionEntry {
        CorrectionLogger.CorrectionEntry(
            timestamp: Date.now.addingTimeInterval(-daysAgo * 86_400),
            fieldName: field, originalValue: original, correctedValue: corrected,
            source: "foundationModel", confidence: "high", documentKind: "receipt",
            merchant: merchant
        )
    }

    @Test func examplesFilteredToMerchantAndCapped() {
        let entries = [
            entry(field: "amount", original: "100.00", corrected: "109.00", merchant: "gaincity", daysAgo: 9),
            entry(field: "merchantName", original: "GAIN CTY", corrected: "Gain City", merchant: "gaincity", daysAgo: 5),
            entry(field: "amount", original: "1.00", corrected: "2.00", merchant: "gaincity", daysAgo: 2),
            entry(field: "amount", original: "7.00", corrected: "8.00", merchant: "othermart", daysAgo: 1),
        ]
        let examples = CorrectionLogger.fewShotExamples(forNormalizedMerchant: "gaincity", entries: entries)

        #expect(examples.count == 2) // capped, most recent two
        #expect(examples[0].contains("GAIN CTY"))
        #expect(examples[1].contains("2.00"))
        #expect(!examples.joined().contains("7.00")) // other merchant excluded
    }

    @Test func noMerchantMeansNoExamples() {
        let entries = [entry(field: "amount", original: "1", corrected: "2", merchant: nil)]
        #expect(CorrectionLogger.fewShotExamples(forNormalizedMerchant: nil, entries: entries).isEmpty)
        #expect(CorrectionLogger.fewShotExamples(forNormalizedMerchant: "gaincity", entries: entries).isEmpty)
    }

    @Test func longValuesAreClipped() {
        let long = String(repeating: "x", count: 200)
        let entries = [entry(field: "productName", original: long, corrected: "Short", merchant: "gaincity")]
        let example = CorrectionLogger.fewShotExamples(forNormalizedMerchant: "gaincity", entries: entries)[0]
        #expect(example.count < 200)
        #expect(example.contains("…"))
    }

    @Test func preExistingLogLinesDecodeWithoutMerchant() throws {
        // A line written before the merchant field existed must still decode.
        let legacy = """
        {"timestamp":"2026-01-15T10:00:00Z","fieldName":"amount","originalValue":"9.00","correctedValue":"10.00","source":"heuristic","confidence":"low","documentKind":"receipt"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(CorrectionLogger.CorrectionEntry.self, from: Data(legacy.utf8))
        #expect(entry.merchant == nil)
        #expect(entry.fieldName == "amount")
    }
}
