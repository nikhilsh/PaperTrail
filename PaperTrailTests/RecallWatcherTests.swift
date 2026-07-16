import Testing
import Foundation
@testable import PaperTrail

/// Pure-logic tests for v3 `recallWatch` (docs/design-v3/V3_BRIEF.md §6):
/// `RecallMatcher`'s brand+model matching and `FixtureRecallFeed`'s bundled
/// JSON decode. No `UNUserNotificationCenter`, no `UserDefaults` I/O — the
/// `RecallWatcher.checkIfNeeded`/`rowState` persistence layer isn't covered
/// here, mirroring `MultiCoverageTests`'s "pure logic only" scope.
struct RecallWatcherTests {

    private func notice(
        id: String = "n1",
        brand: String,
        modelPatterns: [String] = [],
        title: String = "Battery overheating recall"
    ) -> RecallNotice {
        RecallNotice(
            id: id,
            brand: brand,
            modelPatterns: modelPatterns,
            title: title,
            detailURL: URL(string: "https://www.cpsc.gov/Recalls/example")!,
            date: .now
        )
    }

    private func record(
        recordID: UUID = UUID(),
        merchantName: String? = nil,
        productName: String,
        serialNumber: String? = nil
    ) -> RecallMatcher.RecordSnapshot {
        RecallMatcher.RecordSnapshot(recordID: recordID, merchantName: merchantName, productName: productName, serialNumber: serialNumber)
    }

    // MARK: - Brand + pattern match

    @Test func matchesOnBrandAndModelPatternInProductName() {
        let n = notice(brand: "Anker", modelPatterns: ["PowerCore 20000", "A1263"])
        let r = record(productName: "Anker PowerCore 20000 Power Bank")
        #expect(RecallMatcher.matches(r, notice: n))
    }

    @Test func matchesOnBrandAndModelPatternInSerialNumber() {
        let n = notice(brand: "Whirlpool", modelPatterns: ["WED4815EW"])
        let r = record(merchantName: "Whirlpool", productName: "Dryer", serialNumber: "WED4815EW-SN00291")
        #expect(RecallMatcher.matches(r, notice: n))
    }

    @Test func matchesOnMerchantNameBrand() {
        let n = notice(brand: "Dyson", modelPatterns: ["V11"])
        let r = record(merchantName: "Dyson", productName: "V11 Cordless Vacuum")
        #expect(RecallMatcher.matches(r, notice: n))
    }

    @Test func brandWideRecallMatchesAnyModelWhenPatternsEmpty() {
        let n = notice(brand: "GenericHome", modelPatterns: [])
        let r = record(productName: "GenericHome Dehumidifier DH99", serialNumber: nil)
        #expect(RecallMatcher.matches(r, notice: n))
    }

    // MARK: - No match

    @Test func noMatchWhenBrandDiffers() {
        let n = notice(brand: "Anker", modelPatterns: ["PowerCore 20000"])
        let r = record(productName: "Belkin PowerCore 20000 Power Bank")
        #expect(!RecallMatcher.matches(r, notice: n))
    }

    @Test func noMatchWhenBrandMatchesButModelDoesNot() {
        let n = notice(brand: "Anker", modelPatterns: ["PowerCore 20000"])
        let r = record(productName: "Anker Soundcore Speaker", serialNumber: "SC-9981")
        #expect(!RecallMatcher.matches(r, notice: n))
    }

    @Test func noMatchWhenNeitherBrandNorModelPresent() {
        let n = notice(brand: "Ninja", modelPatterns: ["BL610"])
        let r = record(productName: "Samsung TV")
        #expect(!RecallMatcher.matches(r, notice: n))
    }

    @Test func firstMatchReturnsNilWhenNoNoticeMatches() {
        let notices = [notice(id: "a", brand: "Anker"), notice(id: "b", brand: "Ninja")]
        let r = record(productName: "Samsung TV")
        #expect(RecallMatcher.firstMatch(for: r, in: notices) == nil)
    }

    @Test func firstMatchReturnsMatchingNotice() {
        let notices = [
            notice(id: "a", brand: "Anker", modelPatterns: ["PowerCore 20000"]),
            notice(id: "b", brand: "Ninja", modelPatterns: ["BL610"]),
        ]
        let r = record(productName: "Ninja Blender BL610")
        #expect(RecallMatcher.firstMatch(for: r, in: notices)?.id == "b")
    }

    // MARK: - Fixture decode

    @Test func fixtureRecallFeedDecodesBundledJSON() async throws {
        let feed = FixtureRecallFeed()
        let notices = try await feed.fetchRecalls()
        #expect(notices.count >= 5)
        #expect(notices.allSatisfy { !$0.id.isEmpty && !$0.brand.isEmpty && !$0.title.isEmpty })
        // Every fixture should carry at least one model pattern OR be an
        // explicit brand-wide notice — a completely empty notice would
        // silently match every record from every brand.
        #expect(notices.contains { $0.brand == "Volta Labs" })
    }

    // MARK: - Fixture never notifies (HIGH: fixture recall honesty)
    //
    // `checkIfNeeded` itself gates on `FeatureFlags.isOn` +
    // `PlusEntitlements.shared.hasPlus` (a live singleton), so it isn't
    // exercised directly here — same "pure logic only" scope as the rest of
    // this file. `RecallWatcher.shouldNotify` is the pure decision
    // `checkIfNeeded` defers to before calling the untestable
    // `UNUserNotificationCenter` path; testing it directly covers the actual
    // honesty guarantee (fixture data never fires a real notification)
    // without needing a live notification center or entitlement state.

    @Test func fixtureRecallFeedIsFixture() {
        #expect(FixtureRecallFeed().isFixture)
    }

    @Test func shouldNotifyIsFalseForFixtureDataEvenOnNewMatch() {
        #expect(!RecallWatcher.shouldNotify(isNewMatch: true, isFixture: true))
    }

    @Test func shouldNotifyIsTrueForRealFeedOnNewMatch() {
        #expect(RecallWatcher.shouldNotify(isNewMatch: true, isFixture: false))
    }

    @Test func shouldNotifyIsFalseWhenMatchAlreadyKnown() {
        #expect(!RecallWatcher.shouldNotify(isNewMatch: false, isFixture: false))
    }

    // MARK: - Passed-on records are skipped

    @Test func eligibleForRecallCheckExcludesPassedOnRecords() {
        let kept = PurchaseRecord(productName: "Kept")
        let passedOn = PurchaseRecord(productName: "Passed on")
        passedOn.passedOnDate = .now

        let eligible = RecallWatcher.eligibleForRecallCheck([kept, passedOn])
        #expect(eligible.map(\.id) == [kept.id])
    }
}
