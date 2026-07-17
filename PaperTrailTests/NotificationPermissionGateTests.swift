import Testing
import Foundation
import SwiftData
import UserNotifications
@testable import PaperTrail

/// Coverage for the graceful notification permission funnel's pure decision
/// logic — status → `.proceed`/`.ask`/`.denied`, independent of any UI or
/// `UNUserNotificationCenter` call. `NotificationPermissionGate` itself
/// (async, `@MainActor`, talks to `UNUserNotificationCenter` and SwiftData)
/// isn't exercised here — same split as `SoftAskEligibility` vs.
/// `SoftAskCoordinator`.
struct NotificationPermissionGateTests {

    // MARK: - NotificationPermissionDecision.decision(for:)

    @Test func authorizedProceedsImmediately() {
        #expect(NotificationPermissionDecision.decision(for: .authorized) == .proceed)
    }

    @Test func provisionalAndEphemeralAlsoProceed() {
        // Both deliver notifications without a further prompt — same as
        // `.authorized` for the purposes of this gate.
        #expect(NotificationPermissionDecision.decision(for: .provisional) == .proceed)
        #expect(NotificationPermissionDecision.decision(for: .ephemeral) == .proceed)
    }

    @Test func notDeterminedAsks() {
        #expect(NotificationPermissionDecision.decision(for: .notDetermined) == .ask)
    }

    @Test func deniedShowsTheDeniedSheet() {
        #expect(NotificationPermissionDecision.decision(for: .denied) == .denied)
    }

    // MARK: - AskContext copy — every context must supply distinct, non-empty strings

    @Test func everyContextHasNonEmptyAskCopy() {
        for context: AskContext in [.warranty, .digest, .coverage, .recall] {
            #expect(!context.kicker.isEmpty)
            #expect(!context.title.isEmpty)
            #expect(!context.bodyText.isEmpty)
            #expect(!context.sampleTitle.isEmpty)
            #expect(!context.sampleBody.isEmpty)
            #expect(!context.deniedBody.isEmpty)
        }
    }

    @Test func digestHasItsOwnAskCopyDistinctFromWarranty() {
        // The one context whose ask copy deliberately diverges from the
        // shared warranty/coverage/recall wording (item 2: "e.g. digest:
        // title 'A monthly once-over?'").
        #expect(AskContext.digest.title != AskContext.warranty.title)
        #expect(AskContext.digest.kicker != AskContext.warranty.kicker)
        #expect(AskContext.digest.bodyText != AskContext.warranty.bodyText)
        #expect(AskContext.digest.title == "A monthly once-over?")
    }

    @Test func everyContextNamesWhatItIsInTheDeniedBody() {
        #expect(AskContext.warranty.deniedBody.contains("Warranty reminders"))
        #expect(AskContext.digest.deniedBody.contains("monthly digest"))
        #expect(AskContext.coverage.deniedBody.contains("Coverage reminders"))
        #expect(AskContext.recall.deniedBody.contains("recall"))
    }

    // MARK: - NotificationPermissionGate integration (UserDefaults + injected providers)

    private func makeDefaults() -> UserDefaults {
        let suiteName = "NotificationPermissionGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// In-memory-only container so `reArmIfNeeded`'s reschedule path never
    /// touches the real CloudKit-backed `PaperTrailModelContainer` — same
    /// reasoning `PaperTrailApp` documents for skipping CloudKit preflight
    /// in the unit test host (un-entitled test host deadlock risk).
    @MainActor
    private func makeInMemoryModelContext() -> ModelContext {
        let container = try! ModelContainer(
            for: PurchaseRecord.self, Attachment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @MainActor
    private func makeGate(defaults: UserDefaults, authorizationStatus: UNAuthorizationStatus) -> NotificationPermissionGate {
        let modelContext = makeInMemoryModelContext()
        return NotificationPermissionGate(
            defaults: defaults,
            authorizationStatusProvider: { authorizationStatus },
            modelContextProvider: { modelContext }
        )
    }

    @Test @MainActor func ensurePermissionProceedsImmediatelyWhenAuthorized() async {
        let gate = makeGate(defaults: makeDefaults(), authorizationStatus: .authorized)
        let allowed = await gate.ensurePermission(context: .warranty)
        #expect(allowed)
        #expect(gate.pendingAsk == nil)
        #expect(gate.pendingDenied == nil)
    }

    @Test @MainActor func ensurePermissionPresentsTheDeniedSheetWhenDenied() async {
        let gate = makeGate(defaults: makeDefaults(), authorizationStatus: .denied)
        // `ensurePermission` doesn't suspend for `.denied` — it presents and
        // returns `false` synchronously-from-the-caller's-perspective (no
        // continuation to resume).
        let allowed = await gate.ensurePermission(context: .coverage)
        #expect(!allowed)
        #expect(gate.pendingDenied?.context == .coverage)
        #expect(gate.pendingAsk == nil)
    }

    @Test @MainActor func ensurePermissionPresentsTheAskSheetWhenUndetermined() async {
        let gate = makeGate(defaults: makeDefaults(), authorizationStatus: .notDetermined)
        // `.ask` suspends on the sheet's response — fire the check
        // concurrently with the response so the test doesn't hang.
        async let allowed: Bool = gate.ensurePermission(context: .digest)
        // Give `ensurePermission` a beat to actually present before responding.
        try? await Task.sleep(for: .milliseconds(20))
        #expect(gate.pendingAsk?.context == .digest)
        gate.respondNotNow()
        let result = await allowed
        #expect(!result)
        #expect(gate.pendingAsk == nil)
    }

    @Test @MainActor func presentDeniedDirectlyShowsTheSheetForAnyContext() {
        let gate = makeGate(defaults: makeDefaults(), authorizationStatus: .denied)
        gate.presentDeniedDirectly(context: .recall)
        #expect(gate.pendingDenied?.context == .recall)
        gate.dismissDenied()
        #expect(gate.pendingDenied == nil)
    }

    @Test @MainActor func reArmNoOpsOnTheVeryFirstObservation() async {
        // No prior observation persisted — nothing to compare a transition
        // against, so this must never fire a spurious reschedule for an
        // already-authorized user's very first launch after this feature ships.
        let gate = makeGate(defaults: makeDefaults(), authorizationStatus: .authorized)
        let rearmed = await gate.reArmIfNeeded()
        #expect(!rearmed)
        #expect(gate.lastKnownAuthorizationStatus == .authorized)
    }

    @Test @MainActor func reArmFiresOnlyOnADeniedToAuthorizedTransition() async {
        let defaults = makeDefaults()
        // Seed a prior observation of `.denied`.
        let seedGate = makeGate(defaults: defaults, authorizationStatus: .denied)
        _ = await seedGate.reArmIfNeeded()
        #expect(seedGate.lastKnownAuthorizationStatus == .denied)

        // The user granted permission in Settings and came back.
        let returningGate = makeGate(defaults: defaults, authorizationStatus: .authorized)
        let rearmed = await returningGate.reArmIfNeeded()
        #expect(rearmed)
        #expect(returningGate.lastKnownAuthorizationStatus == .authorized)
    }

    @Test @MainActor func reArmDoesNothingWhenStatusIsUnchanged() async {
        let defaults = makeDefaults()
        let seedGate = makeGate(defaults: defaults, authorizationStatus: .authorized)
        _ = await seedGate.reArmIfNeeded()

        let sameGate = makeGate(defaults: defaults, authorizationStatus: .authorized)
        let rearmed = await sameGate.reArmIfNeeded()
        #expect(!rearmed)
    }

    @Test @MainActor func reArmDoesNothingOnAnAuthorizedToDeniedTransition() async {
        // Only a move TOWARD authorized re-arms anything — losing permission
        // has nothing to reschedule.
        let defaults = makeDefaults()
        let seedGate = makeGate(defaults: defaults, authorizationStatus: .authorized)
        _ = await seedGate.reArmIfNeeded()

        let revokedGate = makeGate(defaults: defaults, authorizationStatus: .denied)
        let rearmed = await revokedGate.reArmIfNeeded()
        #expect(!rearmed)
    }
}
