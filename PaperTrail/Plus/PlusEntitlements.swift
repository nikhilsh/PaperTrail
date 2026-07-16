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

        /// Set once, the first time a real entitlement is ever seen — never
        /// cleared, even after lapse. Distinguishes "lapsed member" (show the
        /// quiet renew band) from "never subscribed" (show the plain Plus
        /// band) — see `isLapsed`.
        static let wasEverMember = "plus.wasEverMember"

        /// Product ID of the last active membership seen. Cosmetic/
        /// diagnostic only — the lapsed-state renew band always re-pitches
        /// the annual plan regardless (docs/design-v2/V2_BRIEF.md §1
        /// post-purchase: "Renew your card — S$29.98/yr").
        static let lastPlanProductID = "plus.lastPlanProductID"
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

    /// Persisted once a real entitlement is ever seen — never cleared, even
    /// after lapse (see `Key.wasEverMember`).
    private(set) var wasEverMember: Bool

    /// The product ID of the last active membership seen — see
    /// `Key.lastPlanProductID`.
    private(set) var lastPlanProductID: String?

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
        self.wasEverMember = PlusConfig.enabled ? defaults.bool(forKey: Key.wasEverMember) : false
        self.lastPlanProductID = PlusConfig.enabled ? defaults.string(forKey: Key.lastPlanProductID) : nil
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

    /// Pure lapse precedence (docs/design-v2/V2_BRIEF.md §1 post-purchase,
    /// ANIMATION_SPEC.md §9): "lapsed" means the account was a real Plus
    /// member at some point and isn't now — never true for someone who
    /// never subscribed, so the free tier never sees a guilt-trip band.
    /// `nonisolated` — testable without hopping onto `@MainActor`.
    nonisolated static func isLapsed(wasEverMember: Bool, hasPlus: Bool) -> Bool {
        wasEverMember && !hasPlus
    }

    /// Whether Settings should show the quiet "Renew your card" band instead
    /// of the ordinary Plus band on the free-tier library card.
    var isLapsed: Bool {
        Self.isLapsed(wasEverMember: wasEverMember, hasPlus: hasPlus)
    }

    /// Picks which of several simultaneously-"current" entitlements should
    /// drive the membership card, for the (rare but real) case where more
    /// than one is current at once — e.g. a legacy lifetime purchase
    /// alongside a live subscription; `Transaction.currentEntitlements`
    /// yields both, since a lifetime entitlement never expires. An active
    /// subscription (has an `expirationDate`) always wins over a lifetime
    /// entitlement (no expiration); among subscriptions, the one expiring
    /// latest wins. `nil` if `candidates` is empty. `nonisolated` and
    /// StoreKit-free — callers pass a closure extracting the plain
    /// `Date?` rather than a live `StoreKit.Transaction` shape, so this is
    /// testable without a StoreKit session (`MembershipCardStateTests`).
    nonisolated static func preferredMembership<T>(
        among candidates: [T],
        expirationDate: (T) -> Date?
    ) -> T? {
        candidates.max { lhs, rhs in
            switch (expirationDate(lhs), expirationDate(rhs)) {
            case let (.some(left), .some(right)):
                return left < right   // later expiration wins
            case (.none, .some):
                return true            // lhs is lifetime, rhs is a live subscription
            case (.some, .none):
                return false           // lhs is a live subscription, rhs is lifetime
            case (.none, .none):
                return false           // both lifetime — keep as tied
            }
        }
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
        var active: (productID: String, expirationDate: Date?, isIntroductory: Bool)?

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard isPlusProduct(transaction.productID) else { continue }
                entitled = true
                active = (transaction.productID, transaction.expirationDate, transaction.offerType == .introductory)
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

        if let active {
            markWasEverMember(productID: active.productID)
        }
        await updateRenewalReminder(active: active)
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        switch update {
        case .verified(let transaction):
            let isPlus = isPlusProduct(transaction.productID)
            if isPlus {
                logEvent("Transaction update: \(transaction.productID) verified")
            }
            await transaction.finish()
            if isPlus {
                // Re-derive from `currentEntitlements` (rather than just
                // flipping `hasPlus` to true) so revocations/lapses
                // surfaced via `Transaction.updates` also reschedule/cancel
                // the renewal reminder and refresh the lapsed-state flags.
                await refreshFromCurrentEntitlements()
            }
        case .unverified(let transaction, let error):
            AppLogger.error("Plus transaction update unverified for \(transaction.productID): \(error.localizedDescription)", category: "plus")
            logEvent("Transaction update unverified: \(transaction.productID)")
        @unknown default:
            break
        }
    }

    /// Persists the "was ever a member" flag + last plan seen — never
    /// cleared, even after lapse (see `isLapsed`).
    private func markWasEverMember(productID: String) {
        if !wasEverMember {
            wasEverMember = true
            defaults.set(true, forKey: Key.wasEverMember)
        }
        lastPlanProductID = productID
        defaults.set(productID, forKey: Key.lastPlanProductID)
    }

    /// Renewal-reminder wiring (docs/design-v2/V2_BRIEF.md §4): annual plan
    /// only — cancelled outright for monthly/lifetime/no-entitlement. During
    /// the 14-day intro trial, the 14-day-before-renewal reminder would fire
    /// before (or right at) the trial's own start, so a trial period gets
    /// the shorter TRIAL-ENDING reminder (3 days before the trial's own
    /// expiration/billing date) instead — never both at once for the same
    /// entitlement. Reschedules from live StoreKit pricing so the reminder
    /// body always quotes the real charge.
    ///
    /// Offline safety: a `Product.products(for:)` fetch failure (no network)
    /// must NOT cancel an already-scheduled reminder — that would silently
    /// drop the one notification the honest-renewal promise depends on, just
    /// because this particular refresh happened to run offline. Only a real
    /// lapse/monthly/lifetime state (the guard above) cancels; a fetch
    /// failure here just leaves whatever's already scheduled alone and
    /// retries on the next refresh.
    private func updateRenewalReminder(active: (productID: String, expirationDate: Date?, isIntroductory: Bool)?) async {
        guard let active, active.productID == PlusConfig.ProductID.yearly,
              let expirationDate = active.expirationDate else {
            RenewalReminder.cancel()
            RenewalReminder.cancelTrialEnding()
            return
        }
        guard let product = try? await Product.products(for: [PlusConfig.ProductID.yearly]).first else {
            logEvent("Renewal reminder: products fetch failed, keeping existing schedule")
            return
        }
        if active.isIntroductory {
            RenewalReminder.cancel()
            RenewalReminder.scheduleTrialEnding(expirationDate: expirationDate, priceText: product.displayPrice)
        } else {
            RenewalReminder.cancelTrialEnding()
            RenewalReminder.scheduleAnnual(expirationDate: expirationDate, priceText: product.displayPrice)
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
