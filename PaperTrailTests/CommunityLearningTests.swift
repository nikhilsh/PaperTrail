import Testing
import Foundation
@testable import PaperTrail

/// Community-learning pipeline (opt-out, anonymized, majority-aggregated):
/// payload building + scrubbing, hint decoding, and the never-authoritative
/// confidence cap.
struct CommunityLearningTests {

    private func entry(field: String = "amount", original: String = "100.00",
                       corrected: String = "109.00", merchant: String? = "gaincity") -> CorrectionLogger.CorrectionEntry {
        CorrectionLogger.CorrectionEntry(
            timestamp: .now, fieldName: field, originalValue: original,
            correctedValue: corrected, source: "foundationModel",
            confidence: "high", documentKind: "invoice", merchant: merchant
        )
    }

    // MARK: - Contribution payloads

    @Test func payloadsCarryAnonymousInstallAndMerchant() {
        let payloads = CommunityLearning.payloads(from: [entry()], installID: "ABC-123")
        #expect(payloads.count == 1)
        #expect(payloads[0].installId == "ABC-123")
        #expect(payloads[0].merchantKey == "gaincity")
        #expect(payloads[0].fieldName == "amount")
    }

    @Test func entriesWithoutMerchantAreNotContributed() {
        let payloads = CommunityLearning.payloads(from: [entry(merchant: nil)], installID: "ABC")
        #expect(payloads.isEmpty)
    }

    @Test func scrubRedactsEmailsPhonesAndCapsLength() {
        #expect(CommunityLearning.scrub("contact me@nikhil.sh today") == "contact [redacted] today")
        #expect(CommunityLearning.scrub("call +65 9296 0901 now") == "call [redacted] now")
        #expect(CommunityLearning.scrub("LG Washer 10/6KG") == "LG Washer 10/6KG") // products untouched

        let long = String(repeating: "y", count: 500)
        let scrubbed = CommunityLearning.scrub(long)
        #expect(scrubbed.count == 121) // 120 + ellipsis
    }

    @Test func payloadEncodesSnakeCaseForPostgREST() throws {
        let payloads = CommunityLearning.payloads(from: [entry()], installID: "ID")
        let json = String(data: try JSONEncoder().encode(payloads), encoding: .utf8) ?? ""
        #expect(json.contains("\"install_id\""))
        #expect(json.contains("\"merchant_key\""))
        #expect(json.contains("\"corrected_value\""))
    }

    // MARK: - Community hints

    @Test func decodesAggregateRowsAndIndexesByMerchant() throws {
        let json = """
        [{"merchant_key":"gaincity","display_name":"Gain City","document_kind":"invoice",
          "currency":"SGD","category":"Appliances","contributors":7}]
        """
        let hints = try CommunityLearning.decodeHints(Data(json.utf8))
        let hint = try #require(hints["gaincity"])
        #expect(hint.displayName == "Gain City")
        #expect(hint.contributors == 7)
    }

    @Test func communityContextIsNeverAuthoritative() {
        let popular = CommunityMerchantHint(
            merchantKey: "gaincity", displayName: "Gain City",
            documentKind: "invoice", currency: "SGD", category: "Appliances",
            contributors: 9_999
        )
        let context = popular.learningContext()
        #expect(context.confidence <= 0.45)
        #expect(!context.isAuthoritative) // personal profiles always outrank
        #expect(context.likelyDocumentKind == .invoice)
        #expect(context.currencySuggestion == "SGD")

        let sparse = CommunityMerchantHint(
            merchantKey: "corner", displayName: nil, documentKind: nil,
            currency: nil, category: nil, contributors: 3
        )
        #expect(abs(sparse.learningContext().confidence - 0.3) < 0.0001)
    }
}
