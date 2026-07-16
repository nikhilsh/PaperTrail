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

        /// Debug-only local override (`PlusDebugView` "Simulate Plus").
        /// Only ever able to grant `hasPlus` when `PlusConfig
        /// .debugConsoleEnabled` is `true` — a compile-time constant — so
        /// this key is inert by construction in a store build.
        static let simulateOverride = "plus.debug.simulateOverride"
    }

    /// Normalized outcome of a StoreKit purchase attempt, shared by
    /// `PaywallView` and `PlusDebugView` so both purchase paths report the
    /// same vocabulary and log the same way.
    enum PurchaseOutcome: Equatable {
        case success
        case userCancelled
        case pending
        case failed(String)

        var summary: String {
            switch self {
            case .success: return "Success"
            case .userCancelled: return "Cancelled"
            case .pending: return "Pending approval"
            case .failed(let message): return "Failed: \(message)"
            }
        }
    }

    /// The real, StoreKit-derived entitlement — never influenced by the
    /// debug override below. Kept in sync with `Key.hasPlus` in `UserDefaults`.
    private(set) var realHasPlus: Bool

    /// Debug-only local override so gates/paywall UI can be exercised on a
    /// sandbox Ad Hoc build without a live purchase (`PlusDebugView`
    /// "Simulate Plus"). Persisted so it survives relaunch during a test
    /// session. Ignored unless `PlusConfig.debugConsoleEnabled` — see
    /// `effectiveHasPlus`.
    var simulateOverride: Bool {
        didSet {
            guard simulateOverride != oldValue else { return }
            defaults.set(simulateOverride, forKey: Key.simulateOverride)
            logEvent("Simulate Plus override set to \(simulateOverride)")
        }
    }

    /// Last ~50 lines of purchase/restore/entitlement activity, newest last,
    /// for `PlusDebugView`'s event log. Every entry is also mirrored to
    /// `AppLogger.info(category: "plus")`, so the same flow is queryable in
    /// Sentry structured logs without a device. Never contains receipts,
    /// JWS tokens, or other PII — product IDs and outcomes only.
    private(set) var eventLog: [String] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Flag off: always read as "no Plus" — never trust a stale persisted
        // value from a build where the flag was once on.
        self.realHasPlus = PlusConfig.enabled ? defaults.bool(forKey: Key.hasPlus) : false
        self.simulateOverride = defaults.bool(forKey: Key.simulateOverride)
    }

    /// The entitlement the rest of the app reads (gates, `PaywallView`,
    /// `SettingsView`): the real StoreKit-derived value, OR the debug
    /// override — see `effectiveHasPlus` for the precedence rule.
    var hasPlus: Bool {
        Self.effectiveHasPlus(real: realHasPlus, simulateOverride: simulateOverride, debugConsoleEnabled: PlusConfig.debugConsoleEnabled)
    }

    /// Pure precedence logic, extracted for testability (see
    /// PlusGateTests): the real entitlement always wins; the debug override
    /// only ever adds Plus, and only when `debugConsoleEnabled` is `true`
    /// (impossible in a store build, since that flag is a compile-time
    /// constant). `nonisolated` — touches no actor state.
    nonisolated static func effectiveHasPlus(real: Bool, simulateOverride: Bool, debugConsoleEnabled: Bool) -> Bool {
        real || (simulateOverride && debugConsoleEnabled)
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
        logEvent("Starting PlusEntitlements")

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
        logEvent("Restore requested")
        do {
            try await AppStore.sync()
        } catch {
            AppLogger.error("PlusEntitlements restore failed: \(error.localizedDescription)", category: "plus")
            logEvent("Restore failed: \(error.localizedDescription)")
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

    /// Purchase a product and report a normalized outcome. Shared by
    /// `PaywallView` and `PlusDebugView`'s direct buy buttons so there's one
    /// purchase code path, one place that finishes transactions, and one
    /// place that logs. Never logs receipts or JWS tokens — product IDs and
    /// outcomes only.
    func purchase(_ product: Product) async -> PurchaseOutcome {
        logEvent("Purchase attempt: \(product.id)")
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshFromCurrentEntitlements()
                    logEvent("Purchase verified: \(product.id)")
                    return .success
                case .unverified(_, let error):
                    AppLogger.error("Plus purchase unverified for \(product.id): \(error.localizedDescription)", category: "plus")
                    logEvent("Purchase unverified: \(product.id)")
                    return .failed(error.localizedDescription)
                @unknown default:
                    logEvent("Purchase verification result unknown: \(product.id)")
                    return .failed("Unknown verification result")
                }
            case .userCancelled:
                logEvent("Purchase cancelled: \(product.id)")
                return .userCancelled
            case .pending:
                logEvent("Purchase pending: \(product.id)")
                return .pending
            @unknown default:
                logEvent("Purchase result unknown: \(product.id)")
                return .failed("Unknown purchase result")
            }
        } catch {
            AppLogger.error("Plus purchase failed for \(product.id): \(error.localizedDescription)", category: "plus")
            logEvent("Purchase failed: \(product.id) — \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Internal

    private func refreshFromCurrentEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard isPlusProduct(transaction.productID) else { continue }
                entitled = true
            case .unverified(let transaction, let error):
                guard isPlusProduct(transaction.productID) else { continue }
                AppLogger.error("Plus entitlement unverified for \(transaction.productID): \(error.localizedDescription)", category: "plus")
                logEvent("Entitlement unverified: \(transaction.productID)")
            @unknown default:
                continue
            }
        }
        logEvent("Entitlement refresh: hasPlus=\(entitled)")
        setHasPlus(entitled)
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        switch update {
        case .verified(let transaction):
            if isPlusProduct(transaction.productID) {
                logEvent("Transaction update: \(transaction.productID) verified")
                setHasPlus(true)
            }
            await transaction.finish()
        case .unverified(let transaction, let error):
            AppLogger.error("Plus transaction update unverified for \(transaction.productID): \(error.localizedDescription)", category: "plus")
            logEvent("Transaction update unverified: \(transaction.productID)")
        @unknown default:
            break
        }
    }

    private func isPlusProduct(_ productID: String) -> Bool {
        PlusConfig.ProductID.all.contains(productID)
    }

    private func setHasPlus(_ value: Bool) {
        realHasPlus = value
        defaults.set(value, forKey: Key.hasPlus)
    }

    /// Appends a timestamped line to the in-memory ring buffer (last ~50,
    /// for `PlusDebugView`) and mirrors it to `AppLogger.info`. This is the
    /// single place that writes to `eventLog` — every purchase/restore/
    /// update path above routes through it.
    private func logEvent(_ message: String) {
        let stamped = "\(Self.logTimestamp.string(from: .now))  \(message)"
        eventLog.append(stamped)
        if eventLog.count > 50 {
            eventLog.removeFirst(eventLog.count - 50)
        }
        AppLogger.info(message, category: "plus")
    }
}
