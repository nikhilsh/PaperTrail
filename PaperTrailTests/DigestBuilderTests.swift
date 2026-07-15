import Testing
import Foundation
@testable import PaperTrail

/// Pure logic tests for `DigestBuilder`: no SwiftData, no notification APIs —
/// value snapshots in, `DigestSummary` out. `now` is pinned per test so the
/// 60-day/7-day boundary math never races the clock.
struct DigestBuilderTests {

    private let now = Date(timeIntervalSince1970: 1_752_000_000) // fixed anchor, arbitrary

    private func daysFromNow(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: now)!
    }

    // MARK: - Empty

    @Test func emptyInputIsEmptyDigest() {
        let summary = DigestBuilder.build(from: [], now: now)
        #expect(summary.isEmpty)
        #expect(summary.headline == "")
    }

    @Test func recordsWithNothingUpcomingIsEmptyDigest() {
        // Warranty already expired, no return window, already registered —
        // nothing in this record is digest-worthy.
        let record = DigestRecordSnapshot(
            productName: "Old Toaster",
            warrantyExpiryDate: daysFromNow(-10),
            isRegistered: true
        )
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.isEmpty)
    }

    // MARK: - Singular / plural headline

    @Test func singularWarrantyHeadline() {
        // isRegistered: true keeps this record out of the unregistered-count
        // clause, so the headline is exactly the one warranty part.
        let record = DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(10), isRegistered: true)
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.expiringWarrantyCount == 1)
        #expect(summary.headline == "1 warranty ends within 60 days")
    }

    @Test func pluralWarrantyHeadline() {
        let records = [
            DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(10), isRegistered: true),
            DigestRecordSnapshot(productName: "Kettle", warrantyExpiryDate: daysFromNow(20), isRegistered: true),
        ]
        let summary = DigestBuilder.build(from: records, now: now)
        #expect(summary.expiringWarrantyCount == 2)
        #expect(summary.headline == "2 warranties end within 60 days")
    }

    @Test func singularReturnWindowHeadline() {
        let record = DigestRecordSnapshot(productName: "Lamp", returnDeadline: daysFromNow(2))
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.closingReturnCount == 1)
        #expect(summary.headline.contains("1 return window closes"))
    }

    @Test func pluralReturnWindowHeadline() {
        let records = [
            DigestRecordSnapshot(productName: "Lamp", returnDeadline: daysFromNow(2)),
            DigestRecordSnapshot(productName: "Rug", returnDeadline: daysFromNow(4)),
        ]
        let summary = DigestBuilder.build(from: records, now: now)
        #expect(summary.closingReturnCount == 2)
        #expect(summary.headline.contains("2 return windows close"))
    }

    @Test func singularUnregisteredHeadline() {
        let record = DigestRecordSnapshot(
            productName: "Mixer", warrantyExpiryDate: daysFromNow(200), isRegistered: false
        )
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.unregisteredActiveCount == 1)
        #expect(summary.headline.contains("1 unregistered item is still under warranty"))
    }

    @Test func pluralUnregisteredHeadline() {
        let records = [
            DigestRecordSnapshot(productName: "Mixer", warrantyExpiryDate: daysFromNow(200), isRegistered: false),
            DigestRecordSnapshot(productName: "Fan", warrantyExpiryDate: daysFromNow(300), isRegistered: false),
        ]
        let summary = DigestBuilder.build(from: records, now: now)
        #expect(summary.unregisteredActiveCount == 2)
        #expect(summary.headline.contains("2 unregistered items are still under warranty"))
    }

    @Test func headlineJoinsMultiplePartsWithSeparator() {
        let records = [
            DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(10), isRegistered: true),
            DigestRecordSnapshot(productName: "Lamp", returnDeadline: daysFromNow(2)),
        ]
        let summary = DigestBuilder.build(from: records, now: now)
        let parts = summary.headline.components(separatedBy: " · ")
        #expect(parts.count == 2)
    }

    // MARK: - 60-day warranty boundary

    @Test func warrantyExpiringExactlyAt60DaysIsIncluded() {
        let record = DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(60))
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.expiringWarrantyCount == 1)
    }

    @Test func warrantyExpiringAt61DaysIsExcluded() {
        let record = DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(61))
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.expiringWarrantyCount == 0)
    }

    @Test func alreadyExpiredWarrantyIsExcludedFromExpiringSoon() {
        let record = DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(-1))
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.expiringWarrantyCount == 0)
    }

    // MARK: - 7-day return-window boundary

    @Test func returnWindowClosingExactlyAt7DaysIsIncluded() {
        let record = DigestRecordSnapshot(productName: "Lamp", returnDeadline: daysFromNow(7))
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.closingReturnCount == 1)
    }

    @Test func returnWindowClosingAt8DaysIsExcluded() {
        let record = DigestRecordSnapshot(productName: "Lamp", returnDeadline: daysFromNow(8))
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.closingReturnCount == 0)
    }

    @Test func alreadyClosedReturnWindowIsExcluded() {
        let record = DigestRecordSnapshot(productName: "Lamp", returnDeadline: daysFromNow(-1))
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.closingReturnCount == 0)
    }

    // MARK: - Soonest-3 ordering

    @Test func soonestExpiringIsSortedAndCappedAtThree() {
        let records = [
            DigestRecordSnapshot(productName: "D", warrantyExpiryDate: daysFromNow(40)),
            DigestRecordSnapshot(productName: "A", warrantyExpiryDate: daysFromNow(5)),
            DigestRecordSnapshot(productName: "C", warrantyExpiryDate: daysFromNow(30)),
            DigestRecordSnapshot(productName: "B", warrantyExpiryDate: daysFromNow(15)),
        ]
        let summary = DigestBuilder.build(from: records, now: now)
        #expect(summary.expiringWarrantyCount == 4)
        #expect(summary.soonestExpiring.map(\.name) == ["A", "B", "C"])
        #expect(summary.soonestExpiring.map(\.daysLeft) == [5, 15, 30])
    }

    // MARK: - Per-currency totals

    @Test func totalsAreGroupedPerCurrency() {
        let records = [
            DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(10), amount: 200, currency: "SGD"),
            DigestRecordSnapshot(productName: "Kettle", warrantyExpiryDate: daysFromNow(20), amount: 50, currency: "SGD"),
            DigestRecordSnapshot(productName: "Laptop", warrantyExpiryDate: daysFromNow(30), amount: 1500, currency: "USD"),
        ]
        let summary = DigestBuilder.build(from: records, now: now)
        #expect(summary.expiringWarrantyTotals.count == 2)
        let sgd = summary.expiringWarrantyTotals.first { $0.currency == "SGD" }
        let usd = summary.expiringWarrantyTotals.first { $0.currency == "USD" }
        #expect(sgd?.amount == 250)
        #expect(usd?.amount == 1500)
    }

    @Test func totalsExcludeRecordsOutsideTheExpiringWindow() {
        let records = [
            DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(10), amount: 200, currency: "SGD"),
            DigestRecordSnapshot(productName: "Sofa", warrantyExpiryDate: daysFromNow(300), amount: 1000, currency: "SGD"),
        ]
        let summary = DigestBuilder.build(from: records, now: now)
        #expect(summary.expiringWarrantyTotals.first { $0.currency == "SGD" }?.amount == 200)
    }

    @Test func missingCurrencyDefaultsToSGD() {
        let record = DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(10), amount: 100, currency: nil)
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.expiringWarrantyTotals == [DigestCurrencyTotal(currency: "SGD", amount: 100)])
    }

    // MARK: - Unregistered count

    @Test func unregisteredCountsOnlyActiveWarranties() {
        let records = [
            // Unregistered, still active — counts.
            DigestRecordSnapshot(productName: "Mixer", warrantyExpiryDate: daysFromNow(200), isRegistered: false),
            // Unregistered, but already expired — doesn't count.
            DigestRecordSnapshot(productName: "Fan", warrantyExpiryDate: daysFromNow(-5), isRegistered: false),
            // Unregistered, but no warranty tracked at all — doesn't count.
            DigestRecordSnapshot(productName: "Rug", warrantyExpiryDate: nil, isRegistered: false),
            // Registered and active — doesn't count.
            DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(200), isRegistered: true),
        ]
        let summary = DigestBuilder.build(from: records, now: now)
        #expect(summary.unregisteredActiveCount == 1)
    }

    @Test func unregisteredCountIsIndependentOf60DayWindow() {
        // Warranty is 200 days out — well outside the 60-day expiring window
        // — but still counts toward unregisteredActiveCount, since "still
        // active" isn't the same signal as "expiring soon".
        let record = DigestRecordSnapshot(productName: "Mixer", warrantyExpiryDate: daysFromNow(200), isRegistered: false)
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.expiringWarrantyCount == 0)
        #expect(summary.unregisteredActiveCount == 1)
    }

    // A warranty expiring at today's 00:00 is day-equal to `now` under
    // `startOfDay` comparison, so it must count as still-active in both the
    // expiring-soon list and unregisteredActiveCount — the two use the same
    // day-granularity boundary math.
    @Test func warrantyExpiringAtStartOfTodayCountsInBothExpiringAndUnregistered() {
        let startOfToday = Calendar.current.startOfDay(for: now)
        let record = DigestRecordSnapshot(productName: "Mixer", warrantyExpiryDate: startOfToday, isRegistered: false)
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.expiringWarrantyCount == 1)
        #expect(summary.unregisteredActiveCount == 1)
    }

    // MARK: - Notification headline (no currency totals, no day-precision)

    @Test func notificationHeadlineOmitsCurrencyTotals() {
        let record = DigestRecordSnapshot(
            productName: "Blender", warrantyExpiryDate: daysFromNow(10), amount: 200, currency: "SGD", isRegistered: true
        )
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.headline.contains("SGD"))
        #expect(!summary.notificationHeadline.contains("SGD"))
        #expect(!summary.notificationHeadline.contains("200"))
    }

    @Test func notificationHeadlineOmitsDayPrecisionPhrasing() {
        let record = DigestRecordSnapshot(productName: "Lamp", returnDeadline: daysFromNow(2))
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.headline.contains("in 2 days"))
        for phrase in ["today", "tomorrow", "in 2 days"] {
            #expect(!summary.notificationHeadline.contains(phrase))
        }
    }

    @Test func notificationHeadlineMatchesExpectedCopy() {
        let records = [
            DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(10), isRegistered: true),
            DigestRecordSnapshot(productName: "Kettle", warrantyExpiryDate: daysFromNow(20), isRegistered: true),
            DigestRecordSnapshot(productName: "Toaster", warrantyExpiryDate: daysFromNow(30), isRegistered: true),
            DigestRecordSnapshot(productName: "Lamp", returnDeadline: daysFromNow(2)),
        ]
        let summary = DigestBuilder.build(from: records, now: now)
        #expect(summary.notificationHeadline == "3 warranties end soon · 1 return window is closing")
    }

    @Test func notificationHeadlineSingularPhrasing() {
        let record = DigestRecordSnapshot(productName: "Blender", warrantyExpiryDate: daysFromNow(10), isRegistered: true)
        let summary = DigestBuilder.build(from: [record], now: now)
        #expect(summary.notificationHeadline == "1 warranty ends soon")
    }

    @Test func notificationHeadlineEmptyWhenSummaryIsEmpty() {
        let summary = DigestBuilder.build(from: [], now: now)
        #expect(summary.notificationHeadline == "")
    }
}
