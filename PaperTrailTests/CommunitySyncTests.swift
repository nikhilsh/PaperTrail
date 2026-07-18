import Testing
import Foundation
@testable import PaperTrail

/// The community pipeline's delivery model: local JSONL is the queue, a
/// high-water mark decides what's pending, confirmations count as signal,
/// and post-save edits are corrections too.
struct CommunitySyncTests {

    private func entry(
        at seconds: TimeInterval,
        field: String = "merchantName",
        merchant: String? = "ikea"
    ) -> CorrectionLogger.CorrectionEntry {
        CorrectionLogger.CorrectionEntry(
            timestamp: Date(timeIntervalSince1970: seconds),
            fieldName: field,
            originalValue: "IKAE",
            correctedValue: "IKEA",
            source: "foundationModel",
            confidence: "high",
            documentKind: "receipt",
            merchant: merchant
        )
    }

    // MARK: pending()

    @Test func pendingFiltersAtMarkerAndSortsOldestFirst() {
        let entries = [entry(at: 300), entry(at: 100), entry(at: 200)]
        let pending = CommunityLearning.pending(entries: entries, after: 100, cap: 10)
        #expect(pending.map(\.timestamp.timeIntervalSince1970) == [200, 300])
    }

    @Test func pendingZeroMarkerReturnsEverything() {
        let pending = CommunityLearning.pending(entries: [entry(at: 1), entry(at: 2)], after: 0, cap: 10)
        #expect(pending.count == 2)
    }

    @Test func pendingCapKeepsOldestSoMarkerAdvancesSafely() {
        let entries = (1...5).map { entry(at: TimeInterval($0)) }
        let pending = CommunityLearning.pending(entries: entries, after: 0, cap: 3)
        // Oldest first: uploading these and marking through the newest of
        // them (3) leaves 4 and 5 still pending for the next sync.
        #expect(pending.map(\.timestamp.timeIntervalSince1970) == [1, 2, 3])
    }

    // MARK: uploadable()

    @Test func uploadableDropsLegacyMerchantlessEntries() {
        let entries = [
            entry(at: 1, merchant: nil),      // pre-merchant-key log line
            entry(at: 2, merchant: ""),       // empty key
            entry(at: 3, merchant: "ikea"),
        ]
        let shippable = CommunityLearning.uploadable(entries)
        #expect(shippable.map(\.timestamp.timeIntervalSince1970) == [3])
    }

    @Test func legacyEntriesProduceNoPayloadsButMustNotWedgeTheQueue() {
        // The exact build-46 field bug: a backlog of only merchant-less
        // entries yields zero payloads — sync must then advance markers
        // (behavior in syncBacklog) and Diagnostics must not count them.
        let legacy = [entry(at: 1, merchant: nil), entry(at: 2, merchant: nil)]
        #expect(CommunityLearning.payloads(from: legacy, installID: "X").isEmpty)
        #expect(CommunityLearning.uploadable(legacy).isEmpty)
    }

    // MARK: confirmationEntries()

    private func structured(
        merchant: String? = "IKEA",
        currency: String? = "SGD",
        category: String? = "Furniture"
    ) -> StructuredExtractionResult {
        var result = StructuredExtractionResult.empty
        result.source = .heuristic
        result.merchantName = ExtractedField(value: merchant, confidence: .high)
        result.currency = ExtractedField(value: currency, confidence: .medium)
        result.category = ExtractedField(value: category, confidence: .low)
        return result
    }

    @Test func confirmationsOnlyForKeptNonEmptyValues() {
        let entries = CorrectionLogger.confirmationEntries(
            structured: structured(),
            finalMerchantName: "IKEA",     // kept → confirmed
            finalCurrency: "USD",          // changed → not a confirmation
            finalCategory: "Furniture"     // kept → confirmed
        )
        #expect(entries.map(\.fieldName).sorted() == ["category", "merchantName"])
        #expect(entries.allSatisfy { $0.originalValue == $0.correctedValue })
        #expect(entries.allSatisfy { $0.source.hasPrefix("confirmed-") })
    }

    @Test func confirmationsRequireAMerchantKey() {
        let entries = CorrectionLogger.confirmationEntries(
            structured: structured(merchant: nil),
            finalMerchantName: "",
            finalCurrency: "SGD",
            finalCategory: "Furniture"
        )
        #expect(entries.isEmpty)
    }

    @Test func confirmationsSkipEmptyExtractions() {
        let entries = CorrectionLogger.confirmationEntries(
            structured: structured(currency: nil, category: ""),
            finalMerchantName: "IKEA",
            finalCurrency: "SGD",
            finalCategory: ""
        )
        #expect(entries.map(\.fieldName) == ["merchantName"])
    }

    @Test func noStructuredResultMeansNoConfirmations() {
        let entries = CorrectionLogger.confirmationEntries(
            structured: nil, finalMerchantName: "IKEA", finalCurrency: "SGD", finalCategory: "X"
        )
        #expect(entries.isEmpty)
    }

    // MARK: postSaveEditEntries()

    private func snapshot(
        product: String = "LG Fridge",
        merchant: String = "Gain City",
        date: Date = Date(timeIntervalSince1970: 1_750_000_000),
        amount: Double? = 1499.0,
        currency: String = "SGD",
        category: String = "Appliances"
    ) -> CorrectionLogger.RecordSnapshot {
        CorrectionLogger.RecordSnapshot(
            productName: product, merchantName: merchant, purchaseDate: date,
            amount: amount, currency: currency, category: category
        )
    }

    @Test func editDiffLogsChangedFieldsOnly() {
        let entries = CorrectionLogger.postSaveEditEntries(
            before: snapshot(),
            after: snapshot(product: "LG 2 Door Fridge", category: "Kitchen")
        )
        #expect(entries.map(\.fieldName).sorted() == ["category", "productName"])
        #expect(entries.allSatisfy { $0.source == "postSaveEdit" })
        #expect(entries.allSatisfy { $0.merchant == "gain city" })
    }

    @Test func editDiffIgnoresSameDayDateAndSubCentAmount() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let entries = CorrectionLogger.postSaveEditEntries(
            before: snapshot(date: base, amount: 100.00),
            after: snapshot(date: base.addingTimeInterval(3600), amount: 100.004)
        )
        #expect(entries.isEmpty)
    }

    @Test func editDiffNeverTreatsFillInsAsCorrections() {
        let entries = CorrectionLogger.postSaveEditEntries(
            before: snapshot(category: ""),
            after: snapshot(category: "Appliances")
        )
        #expect(entries.isEmpty)
    }

    @Test func editDiffCatchesRealDateAndAmountChanges() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let entries = CorrectionLogger.postSaveEditEntries(
            before: snapshot(date: base, amount: 100.0),
            after: snapshot(date: base.addingTimeInterval(3 * 86_400), amount: 149.0)
        )
        #expect(entries.map(\.fieldName).sorted() == ["amount", "purchaseDate"])
    }
}
