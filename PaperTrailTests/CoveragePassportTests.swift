import Testing
import Foundation
import SwiftData
@testable import PaperTrail

/// Pure-logic tests for the Coverage Passport (v2 design wave, W2):
/// `CoverageLine` Codable round-trip through `PurchaseRecord.coverageLines`
/// (the additive `coverageLinesData` schema field) and the ring's
/// total/remaining/unit math in `coverageRingValues`. No SwiftUI is exercised
/// here — `CoverageRing`'s animation is view code with no device-independent
/// behavior to assert on.
struct CoveragePassportTests {

    // MARK: - CoverageLine round trip

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PurchaseRecord.self, Attachment.self, MerchantProfile.self, ProductCategoryMemory.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A record created without `coverageLinesData` must persist and re-load
    /// with an empty list — the macro-safe default — so existing CloudKit
    /// records migrate via lightweight migration.
    @Test @MainActor func coverageLinesDefaultsToEmpty() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let record = PurchaseRecord(productName: "Fridge")
        context.insert(record)
        try context.save()

        let loaded = try #require(try context.fetch(FetchDescriptor<PurchaseRecord>()).first)
        #expect(loaded.coverageLinesData == nil)
        #expect(loaded.coverageLines == [])
    }

    @Test @MainActor func coverageLinesRoundTripsThroughPersistence() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let record = PurchaseRecord(productName: "Washing machine")
        record.coverageLines = [
            CoverageLine(label: "Parts", covered: true),
            CoverageLine(label: "Accidental damage", covered: false)
        ]
        context.insert(record)
        try context.save()

        let loaded = try #require(try context.fetch(FetchDescriptor<PurchaseRecord>()).first)
        #expect(loaded.coverageLines.count == 2)
        #expect(loaded.coverageLines[0] == CoverageLine(label: "Parts", covered: true))
        #expect(loaded.coverageLines[1] == CoverageLine(label: "Accidental damage", covered: false))
    }

    @Test func coverageLineIsCodableRoundTrip() throws {
        let lines = [CoverageLine(label: "Water damage", covered: false), CoverageLine(label: "Labour", covered: true)]
        let data = try JSONEncoder().encode(lines)
        let decoded = try JSONDecoder().decode([CoverageLine].self, from: data)
        #expect(decoded == lines)
    }

    @Test func coverageLinesSetterToleratesGarbageThenReadsBackEmpty() {
        // Assigning through the computed setter always produces valid JSON, so
        // this just documents the decode-failure fallback stays empty rather
        // than crashing, for a hand-corrupted blob.
        let record = PurchaseRecord(productName: "Test")
        record.coverageLinesData = Data("not json".utf8)
        #expect(record.coverageLines == [])
    }

    // MARK: - coverageRingValues

    private func daysFromNow(_ n: Int, from now: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: now)!
    }

    private func monthsFromNow(_ n: Int, from now: Date = .now) -> Date {
        Calendar.current.date(byAdding: .month, value: n, to: now)!
    }

    @Test func monthsUnitWhenPlentyOfCoverageRemains() {
        let now = Date.now
        let purchase = monthsFromNow(-12, from: now) // bought a year ago
        let expiry = monthsFromNow(12, from: now)    // 12 months left, 24 total
        let values = coverageRingValues(purchaseDate: purchase, expiryDate: expiry, now: now)
        #expect(values.unit == .months)
        #expect(values.remaining == 12)
        #expect(values.total == 24)
    }

    @Test func switchesToDaysUnitUnderTwoMonthsRemaining() {
        let now = Date.now
        let purchase = monthsFromNow(-22, from: now)
        let expiry = daysFromNow(45, from: now) // ~1.5 months left
        let values = coverageRingValues(purchaseDate: purchase, expiryDate: expiry, now: now)
        #expect(values.unit == .days)
        #expect(values.remaining == 45)
    }

    @Test func expiredWarrantyClampsRemainingToZero() {
        let now = Date.now
        let purchase = monthsFromNow(-24, from: now)
        let expiry = daysFromNow(-10, from: now) // expired 10 days ago
        let values = coverageRingValues(purchaseDate: purchase, expiryDate: expiry, now: now)
        #expect(values.remaining == 0)
        #expect(values.total > 0) // still reports a real total span, not zero
    }

    @Test func missingPurchaseDateFallsBackToFullRing() {
        // No purchase date on file — can't know the original window length,
        // so total == remaining (a full ring) rather than guessing.
        let now = Date.now
        let expiry = monthsFromNow(6, from: now)
        let values = coverageRingValues(purchaseDate: nil, expiryDate: expiry, now: now)
        #expect(values.total == values.remaining)
        #expect(values.remaining == 6)
    }

    @Test func missingPurchaseDateWithNoCoverageLeftStillProducesAtLeastOneUnit() {
        // Edge case: no purchase date AND already expired — `total` must
        // never be zero (it's a denominator elsewhere), so it floors to 1.
        let now = Date.now
        let expiry = daysFromNow(-5, from: now)
        let values = coverageRingValues(purchaseDate: nil, expiryDate: expiry, now: now)
        #expect(values.remaining == 0)
        #expect(values.total == 1)
    }

    @Test func unitSuffixesMatchDesignLanguage() {
        #expect(CoverageRingUnit.months.suffix == "mo")
        #expect(CoverageRingUnit.days.suffix == "d")
    }
}
