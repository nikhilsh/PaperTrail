import Testing
import Foundation
@testable import PaperTrail

/// The corrections JSONL is no longer write-only: healthSummary aggregates it
/// (counts only, never values) for Diagnostics.
struct CorrectionInsightsTests {

    private func entry(field: String, daysAgo: Double, source: String = "foundationModel") -> CorrectionLogger.CorrectionEntry {
        CorrectionLogger.CorrectionEntry(
            timestamp: Date.now.addingTimeInterval(-daysAgo * 86_400),
            fieldName: field,
            originalValue: "a", correctedValue: "b",
            source: source, confidence: "high", documentKind: "receipt"
        )
    }

    @Test func summarizesCountsWindowsAndTopField() {
        let entries = [
            entry(field: "amount", daysAgo: 1),
            entry(field: "amount", daysAgo: 5),
            entry(field: "amount", daysAgo: 45),
            entry(field: "merchantName", daysAgo: 2, source: "heuristic"),
            entry(field: "purchaseDate", daysAgo: 90),
        ]
        let health = CorrectionLogger.healthSummary(entries: entries)

        #expect(health.totalCorrections == 5)
        #expect(health.last30Days == 3)
        #expect(health.byField["amount"] == 3)
        #expect(health.mostCorrectedField == "amount")
        #expect(health.bySource["foundationModel"] == 4)
        #expect(health.bySource["heuristic"] == 1)
    }

    @Test func emptyLogYieldsZeroHealth() {
        let health = CorrectionLogger.healthSummary(entries: [])
        #expect(health.totalCorrections == 0)
        #expect(health.last30Days == 0)
        #expect(health.mostCorrectedField == nil)
    }

    @Test func topFieldTieBreaksDeterministically() {
        let entries = [entry(field: "merchantName", daysAgo: 1), entry(field: "amount", daysAgo: 1)]
        let health = CorrectionLogger.healthSummary(entries: entries)
        #expect(health.mostCorrectedField == "amount") // alphabetical on tie
    }
}
