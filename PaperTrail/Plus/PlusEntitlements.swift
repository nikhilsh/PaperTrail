import Foundation
import StoreKit
import Observation

/// Entitlement layer for PaperTrail Plus — wraps StoreKit 2's on-device
/// receipt verification (`Transaction.currentEntitlements` +
/// `Transaction.updates`). No server, consistent with the app's no-account
/// posture (docs/MONETIZATION.md "Technical plan").
///
/// Entirely inert while `PlusConfig.enabled == false`: `start()` and
/// `restore()` no-op, `hasPlus` reads persisted state only (never triggers a
/// StoreKit call), so the store build behaves byte-identically to today.
///
/// Concurrency: `@MainActor`, matching `HouseholdManager` /
/// `HouseholdSyncEngine` (the project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, the ambient default) — the
/// `Transaction.updates` listener `Task` inherits MainActor isolation, so
/// state writes inside it need no manual `Task { @MainActor in }` hop.
@MainActor
@Observable
final class PlusEntitlements {
    static let shared = PlusEntitlements()

    private enum Key {
        /// Last-known entitlement state, persisted so a launch with no
        /// network still shows the right paywall/gate state immediately,
        /// before `Transaction.currentEntitlements` finishes.
        static let hasPlus = "plus.hasPlus"
    }

    private(set) var hasPlus: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Flag off: always read as "no Plus" — never trust a stale persisted
        // value from a build where the flag was once on.
        self.hasPlus = PlusConfig.enabled ? defaults.bool(forKey: Key.hasPlus) : false
    }

    /// Pure gate logic, extracted for testability (see PlusGateTests) and so
    /// `canUseHousehold` below is a one-line delegate rather than duplicated
    /// logic. Household sharing beyond the first member requires Plus; with
    /// the flag off, household sharing is unrestricted (today's behavior).
    /// `nonisolated` — this touches no actor state, so tests can call it
    /// synchronously without hopping onto `@MainActor`.
    nonisolated static func canUseHousehold(flagEnabled: Bool, hasPlus: Bool) -> Bool {
        !flagEnabled || hasPlus
    }

    var canUseHousehold: Bool {
        Self.canUseHousehold(flagEnabled: PlusConfig.enabled, hasPlus: hasPlus)
    }

    // MARK: - Lifecycle

    /// Call once at app launch. No-ops entirely when the flag is off — no
    /// StoreKit call is ever made, so the store build stays byte-identical.
    /// Idempotent: safe to call more than once (cancels any previous listener).
    func start() {
        guard PlusConfig.enabled else { return }
        AppLogger.info("Starting PlusEntitlements", category: "monetization")

        Task { await refreshFromCurrentEntitlements() }

        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    /// `try await AppStore.sync()` then refresh — StoreKit 2 restores
    /// automatically via `currentEntitlements`, but App Review requires an
    /// explicit "Restore purchases" affordance, and it's a legitimate escape
    /// hatch after e.g. a device restore.
    func restore() async {
        guard PlusConfig.enabled else { return }
        do {
            try await AppStore.sync()
        } catch {
            AppLogger.error("PlusEntitlements restore failed: \(error.localizedDescription)", category: "monetization")
        }
        await refreshFromCurrentEntitlements()
    }

    /// Re-check `currentEntitlements` on demand — e.g. right after a
    /// successful purchase in `PaywallView`, so the sheet reflects the new
    /// entitlement immediately rather than waiting for the next
    /// `Transaction.updates` event.
    func refresh() async {
        guard PlusConfig.enabled else { return }
        await refreshFromCurrentEntitlements()
    }

    // MARK: - Internal

    private func refreshFromCurrentEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, isPlusProduct(transaction.productID) else { continue }
            entitled = true
        }
        setHasPlus(entitled)
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        if isPlusProduct(transaction.productID) {
            setHasPlus(true)
        }
        await transaction.finish()
    }

    private func isPlusProduct(_ productID: String) -> Bool {
        PlusConfig.ProductID.all.contains(productID)
    }

    private func setHasPlus(_ value: Bool) {
        hasPlus = value
        defaults.set(value, forKey: Key.hasPlus)
    }
}
