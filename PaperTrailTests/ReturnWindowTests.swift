import Testing
import Foundation
import SwiftData
@testable import PaperTrail

/// Pure logic tests for the return-window countdown feature: deadline math
/// (including end-of-day rounding) and status transitions at the closingSoon /
/// closed boundaries. No notification or UI behavior is exercised here.
struct ReturnWindowTests {

    // MARK: - Model round trip

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PurchaseRecord.self, Attachment.self, MerchantProfile.self, ProductCategoryMemory.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A record created the "old" way (no `returnWindowDays` supplied) must
    /// persist and re-load with the macro-safe `nil` default, so existing
    /// CloudKit records migrate via lightweight migration.
    @Test @MainActor func returnWindowDaysDefaultsCleanly() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let record = PurchaseRecord(productName: "Toaster")
        context.insert(record)
        try context.save()

        let loaded = try #require(try context.fetch(FetchDescriptor<PurchaseRecord>()).first)
        #expect(loaded.returnWindowDays == nil)
        #expect(loaded.returnWindowStatus == .none)
    }

    @Test @MainActor func returnWindowDaysRoundTrips() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let record = PurchaseRecord(productName: "Blender", returnWindowDays: 30)
        context.insert(record)
        try context.save()

        let loaded = try #require(try context.fetch(FetchDescriptor<PurchaseRecord>()).first)
        #expect(loaded.returnWindowDays == 30)
    }

    // MARK: - Status logic

    private func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: .now)!
    }

    private func record(purchasedDaysAgo: Int?, returnWindowDays: Int?) -> PurchaseRecord {
        PurchaseRecord(
            productName: "Test item",
            purchaseDate: purchasedDaysAgo.map { daysAgo($0) },
            returnWindowDays: returnWindowDays
        )
    }

    @Test func noWindowConfiguredIsNone() {
        let r = record(purchasedDaysAgo: 5, returnWindowDays: nil)
        #expect(r.returnDeadline == nil)
        #expect(r.returnWindowStatus == .none)
    }

    @Test func windowWithoutPurchaseDateIsNone() {
        let r = record(purchasedDaysAgo: nil, returnWindowDays: 30)
        #expect(r.returnDeadline == nil)
        #expect(r.returnWindowStatus == .none)
    }

    @Test func openWithPlentyOfDaysLeft() {
        // 30-day window, bought 10 days ago → 20 days left, well above the
        // 3-day closingSoon threshold.
        let r = record(purchasedDaysAgo: 10, returnWindowDays: 30)
        #expect(r.returnWindowStatus == .open(daysLeft: 20))
    }

    @Test func closingSoonAtThreeDayBoundary() {
        // 10-day window, bought 7 days ago → exactly 3 days left → closingSoon.
        let r = record(purchasedDaysAgo: 7, returnWindowDays: 10)
        #expect(r.returnWindowStatus == .closingSoon(daysLeft: 3))
    }

    @Test func openJustAboveThreeDayBoundary() {
        // 10-day window, bought 6 days ago → 4 days left → still open, not closingSoon.
        let r = record(purchasedDaysAgo: 6, returnWindowDays: 10)
        #expect(r.returnWindowStatus == .open(daysLeft: 4))
    }

    @Test func closingSoonOnDeadlineDay() {
        // Window closes today: still open until 23:59:59, so closingSoon(0), not closed.
        let r = record(purchasedDaysAgo: 10, returnWindowDays: 10)
        #expect(r.returnWindowStatus == .closingSoon(daysLeft: 0))
    }

    @Test func closedAfterDeadlinePassed() {
        // Window closed yesterday.
        let r = record(purchasedDaysAgo: 11, returnWindowDays: 10)
        #expect(r.returnWindowStatus == .closed)
    }

    @Test func returnDeadlineIsEndOfDay() throws {
        let r = record(purchasedDaysAgo: 0, returnWindowDays: 5)
        let deadline = try #require(r.returnDeadline)
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: deadline)
        #expect(components.hour == 23)
        #expect(components.minute == 59)
        #expect(components.second == 59)
    }

    @Test func returnDeadlineAddsWindowDaysToPurchaseDate() throws {
        let r = record(purchasedDaysAgo: 0, returnWindowDays: 14)
        let deadline = try #require(r.returnDeadline)
        let expectedDay = Calendar.current.date(byAdding: .day, value: 14, to: .now)!
        #expect(Calendar.current.isDate(deadline, inSameDayAs: expectedDay))
    }

    @Test func isClosingSoonHelper() {
        #expect(ReturnWindowStatus.closingSoon(daysLeft: 2).isClosingSoon == true)
        #expect(ReturnWindowStatus.closingSoon(daysLeft: 0).isClosingSoon == true)
        #expect(ReturnWindowStatus.open(daysLeft: 10).isClosingSoon == false)
        #expect(ReturnWindowStatus.closed.isClosingSoon == false)
        #expect(ReturnWindowStatus.none.isClosingSoon == false)
    }
}
