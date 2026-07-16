import Testing
import Foundation
import UserNotifications
@testable import PaperTrail

/// Coverage for the N1 notification soft-ask trigger predicate — see
/// docs/design-v2/V2_BRIEF.md §4. Two rules: the initial ask fires exactly
/// once, only on the user's very first-ever saved record, only while
/// permission is undetermined; the re-ask fires at most once ever, only once
/// a warranty is genuinely closing in (0–30 days out) and permission is
/// still undetermined.
struct SoftAskCoordinatorTests {

    // MARK: - SoftAskEligibility.shouldShowInitial — full matrix

    /// `>= 1`, not `== 1`: a first-ever save can save more than one record at
    /// once (a multi-item receipt scan saves each line item as its own
    /// record in the same call), which must still count as "the first save"
    /// rather than skip past the threshold and never trigger the ask.
    @Test func showsOnceThereIsAtLeastOneRecordSavedEver() {
        for lifetime in [1, 2, 5, 100] {
            #expect(SoftAskEligibility.shouldShowInitial(
                recordsSavedLifetime: lifetime, authorizationStatus: .notDetermined, hasShownInitial: false
            ))
        }
        #expect(!SoftAskEligibility.shouldShowInitial(
            recordsSavedLifetime: 0, authorizationStatus: .notDetermined, hasShownInitial: false
        ))
    }

    @Test func neverShowsInitialOncePermissionIsDecided() {
        for status: UNAuthorizationStatus in [.authorized, .denied, .provisional, .ephemeral] {
            #expect(!SoftAskEligibility.shouldShowInitial(
                recordsSavedLifetime: 1, authorizationStatus: status, hasShownInitial: false
            ))
        }
    }

    @Test func neverShowsInitialTwice() {
        #expect(!SoftAskEligibility.shouldShowInitial(
            recordsSavedLifetime: 1, authorizationStatus: .notDetermined, hasShownInitial: true
        ))
        // Not once it's already been shown, no matter how many more records
        // pile up afterward.
        #expect(!SoftAskEligibility.shouldShowInitial(
            recordsSavedLifetime: 12, authorizationStatus: .notDetermined, hasShownInitial: true
        ))
    }

    // MARK: - SoftAskEligibility.shouldReAsk — full matrix

    @Test func reAsksOnlyAfterTheInitialAskShowed() {
        #expect(!SoftAskEligibility.shouldReAsk(
            hasShownInitial: false, authorizationStatus: .notDetermined, reAskCount: 0, daysUntilNearestWarrantyExpiry: 10
        ))
        #expect(SoftAskEligibility.shouldReAsk(
            hasShownInitial: true, authorizationStatus: .notDetermined, reAskCount: 0, daysUntilNearestWarrantyExpiry: 10
        ))
    }

    @Test func reAsksAtMostOnceEver() {
        #expect(!SoftAskEligibility.shouldReAsk(
            hasShownInitial: true, authorizationStatus: .notDetermined, reAskCount: 1, daysUntilNearestWarrantyExpiry: 10
        ))
    }

    @Test func neverReAsksOncePermissionIsDecided() {
        for status: UNAuthorizationStatus in [.authorized, .denied, .provisional, .ephemeral] {
            #expect(!SoftAskEligibility.shouldReAsk(
                hasShownInitial: true, authorizationStatus: status, reAskCount: 0, daysUntilNearestWarrantyExpiry: 10
            ))
        }
    }

    @Test func reAsksOnlyWithinThirtyDaysOfExpiry() {
        #expect(!SoftAskEligibility.shouldReAsk(
            hasShownInitial: true, authorizationStatus: .notDetermined, reAskCount: 0, daysUntilNearestWarrantyExpiry: nil
        ))
        #expect(!SoftAskEligibility.shouldReAsk(
            hasShownInitial: true, authorizationStatus: .notDetermined, reAskCount: 0, daysUntilNearestWarrantyExpiry: 31
        ))
        #expect(!SoftAskEligibility.shouldReAsk(
            hasShownInitial: true, authorizationStatus: .notDetermined, reAskCount: 0, daysUntilNearestWarrantyExpiry: -1
        ))
        #expect(SoftAskEligibility.shouldReAsk(
            hasShownInitial: true, authorizationStatus: .notDetermined, reAskCount: 0, daysUntilNearestWarrantyExpiry: 30
        ))
        #expect(SoftAskEligibility.shouldReAsk(
            hasShownInitial: true, authorizationStatus: .notDetermined, reAskCount: 0, daysUntilNearestWarrantyExpiry: 0
        ))
    }

    // MARK: - SoftAskCoordinator.nearestExpiring

    @Test func nearestExpiringPicksTheSoonestRecordWithinThirtyDays() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let far = PurchaseRecord(productName: "Far", warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 45, to: now))
        let soon = PurchaseRecord(productName: "Soon", warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 10, to: now))
        let soonest = PurchaseRecord(productName: "Soonest", warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 3, to: now))
        let expired = PurchaseRecord(productName: "Expired", warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: -3, to: now))
        let noWarranty = PurchaseRecord(productName: "None")

        let result = SoftAskCoordinator.nearestExpiring(records: [far, soon, soonest, expired, noWarranty], now: now)
        #expect(result?.record.productName == "Soonest")
        #expect(result?.days == 3)
    }

    @Test func nearestExpiringReturnsNilWhenNothingIsClose() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let far = PurchaseRecord(productName: "Far", warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 45, to: now))
        #expect(SoftAskCoordinator.nearestExpiring(records: [far], now: now) == nil)
        #expect(SoftAskCoordinator.nearestExpiring(records: [], now: now) == nil)
    }

    // MARK: - SoftAskCoordinator integration (UserDefaults + injected providers)

    /// Fresh, isolated UserDefaults suite per call so tests never share state
    /// with each other or with the app's real defaults.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "SoftAskCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private func makeCoordinator(
        defaults: UserDefaults,
        authorizationStatus: UNAuthorizationStatus,
        hasActiveCover: Bool = false
    ) -> SoftAskCoordinator {
        SoftAskCoordinator(
            defaults: defaults,
            authorizationStatusProvider: { authorizationStatus },
            hasActiveCoverProvider: { hasActiveCover }
        )
    }

    /// `recordSaved` bumps the lifetime counter synchronously (before it
    /// kicks off its own fire-and-forget evaluation Task), so this much is
    /// observable without awaiting anything.
    @Test @MainActor func recordSavedIncrementsLifetimeCountSynchronously() {
        let coordinator = makeCoordinator(defaults: makeDefaults(), authorizationStatus: .notDetermined)
        #expect(coordinator.recordsSavedLifetime == 0)
        coordinator.recordSaved(count: 1, itemName: "Samsung TV", warrantyExpiryDate: nil)
        #expect(coordinator.recordsSavedLifetime == 1)
    }

    /// Seeds `recordsSavedLifetime` directly rather than going through
    /// `recordSaved` (which also kicks off its own fire-and-forget Task),
    /// so `evaluateInitial` can be awaited deterministically without a race.
    private func seedFirstSave(_ defaults: UserDefaults) {
        defaults.set(1, forKey: "softAsk.recordsSavedLifetime")
    }

    @Test @MainActor func firstSaveWithUndeterminedPermissionPresentsTheAsk() async throws {
        let defaults = makeDefaults()
        seedFirstSave(defaults)
        let coordinator = makeCoordinator(defaults: defaults, authorizationStatus: .notDetermined)
        let shown = await coordinator.evaluateInitial(itemName: "Samsung TV", warrantyExpiryDate: nil, settleGracePeriod: false)

        #expect(shown)
        #expect(coordinator.pendingAsk?.itemName == "Samsung TV")
        // hasShownInitial burns when the sheet actually renders (`markShown`,
        // driven by the presented sheet's `onAppear`), not merely when it's
        // scheduled to present.
        #expect(!coordinator.hasShownInitial)
        coordinator.markShown(try #require(coordinator.pendingAsk))
        #expect(coordinator.hasShownInitial)
    }

    @Test @MainActor func secondSaveNeverPresentsTheAsk() async throws {
        let defaults = makeDefaults()
        seedFirstSave(defaults)
        let coordinator = makeCoordinator(defaults: defaults, authorizationStatus: .notDetermined)
        _ = await coordinator.evaluateInitial(itemName: "First item", warrantyExpiryDate: nil, settleGracePeriod: false)
        coordinator.markShown(try #require(coordinator.pendingAsk))
        coordinator.respondNotNow()

        let secondCoordinator = makeCoordinator(defaults: defaults, authorizationStatus: .notDetermined)
        let shown = await secondCoordinator.evaluateInitial(itemName: "Second item", warrantyExpiryDate: nil, settleGracePeriod: false)
        #expect(!shown)
        #expect(secondCoordinator.pendingAsk == nil)
    }

    @Test @MainActor func neverPresentsOverAnActiveCover() async {
        let defaults = makeDefaults()
        seedFirstSave(defaults)
        let coordinator = makeCoordinator(defaults: defaults, authorizationStatus: .notDetermined, hasActiveCover: true)
        let shown = await coordinator.evaluateInitial(itemName: "Item", warrantyExpiryDate: nil, settleGracePeriod: false)
        #expect(!shown)
        #expect(coordinator.pendingAsk == nil)
        // Left unshown, so the next eligible moment can still show it.
        #expect(!coordinator.hasShownInitial)
    }

    @Test @MainActor func neverPresentsOncePermissionIsAlreadyDecided() async {
        let defaults = makeDefaults()
        seedFirstSave(defaults)
        let coordinator = makeCoordinator(defaults: defaults, authorizationStatus: .denied)
        let shown = await coordinator.evaluateInitial(itemName: "Item", warrantyExpiryDate: nil, settleGracePeriod: false)
        #expect(!shown)
        #expect(coordinator.pendingAsk == nil)
    }

    @Test @MainActor func reAskFiresOnceAfterDeclineWhenAWarrantyIsClosingIn() async throws {
        let defaults = makeDefaults()
        seedFirstSave(defaults)
        let initial = makeCoordinator(defaults: defaults, authorizationStatus: .notDetermined)
        _ = await initial.evaluateInitial(itemName: "First item", warrantyExpiryDate: nil, settleGracePeriod: false)
        initial.markShown(try #require(initial.pendingAsk))
        initial.respondNotNow()
        #expect(initial.hasShownInitial)
        #expect(initial.reAskCount == 0)

        let now = Date()
        let closingIn = PurchaseRecord(productName: "Closing soon", warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 5, to: now))
        let reAskCoordinator = makeCoordinator(defaults: defaults, authorizationStatus: .notDetermined)
        let fired = await reAskCoordinator.checkReAsk(records: [closingIn])
        #expect(fired)
        #expect(reAskCoordinator.pendingAsk?.itemName == "Closing soon")
        // Not burned yet — only `markShown` (the sheet's own `onAppear`) spends it.
        #expect(reAskCoordinator.reAskCount == 0)
        reAskCoordinator.markShown(try #require(reAskCoordinator.pendingAsk))
        #expect(reAskCoordinator.reAskCount == 1)

        // A second closing-in record must not trigger a second re-ask, ever.
        reAskCoordinator.respondNotNow()
        let anotherClosingIn = PurchaseRecord(productName: "Also closing", warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 2, to: now))
        let firedAgain = await reAskCoordinator.checkReAsk(records: [anotherClosingIn])
        #expect(!firedAgain)
    }

    /// Item 3: concurrent `checkReAsk` calls must not double-increment
    /// `reAskCount` — the single-flight guard plus the post-await re-check of
    /// `pendingAsk == nil` together make sure only the first of two racing
    /// callers actually presents.
    @Test @MainActor func concurrentCheckReAskCallsOnlyFireOnce() async throws {
        let defaults = makeDefaults()
        seedFirstSave(defaults)
        let initial = makeCoordinator(defaults: defaults, authorizationStatus: .notDetermined)
        _ = await initial.evaluateInitial(itemName: "First item", warrantyExpiryDate: nil, settleGracePeriod: false)
        initial.markShown(try #require(initial.pendingAsk))
        initial.respondNotNow()

        let now = Date()
        let closingIn = PurchaseRecord(productName: "Closing soon", warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 5, to: now))

        // A status provider with an artificial delay widens the race window
        // between the two concurrent `checkReAsk` calls below.
        let reAskCoordinator = SoftAskCoordinator(
            defaults: defaults,
            authorizationStatusProvider: {
                try? await Task.sleep(for: .milliseconds(20))
                return .notDetermined
            },
            hasActiveCoverProvider: { false }
        )

        async let first = reAskCoordinator.checkReAsk(records: [closingIn])
        async let second = reAskCoordinator.checkReAsk(records: [closingIn])
        let results = await [first, second]

        #expect(results.filter { $0 }.count == 1)
        if let ask = reAskCoordinator.pendingAsk {
            reAskCoordinator.markShown(ask)
        }
        #expect(reAskCoordinator.reAskCount == 1)
    }

    @Test @MainActor func reAskNeverFiresBeforeTheInitialAskEverShowed() async {
        let now = Date()
        let closingIn = PurchaseRecord(productName: "Closing soon", warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 5, to: now))
        let coordinator = makeCoordinator(defaults: makeDefaults(), authorizationStatus: .notDetermined)
        let fired = await coordinator.checkReAsk(records: [closingIn])
        #expect(!fired)
    }
}
