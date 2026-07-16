import SwiftUI
import UserNotifications

// MARK: - SoftAskEligibility (docs/design-v2/V2_BRIEF.md §4 N1)
//
// Pure eligibility rules for the notification soft-ask. `nonisolated` for the
// same reason as `ReviewEligibility` (see ReviewPrompter.swift) — plain,
// synchronous, fully testable, no main-actor pin needed even though the app
// target defaults new declarations to `@MainActor`.

enum SoftAskEligibility {
    /// The initial ask: only the user's very first successful record save
    /// ever triggers it ("total records saved == 1 (first ever)"), only
    /// while permission is still undetermined, and only if it's never been
    /// shown before.
    nonisolated static func shouldShowInitial(
        recordsSavedLifetime: Int,
        authorizationStatus: UNAuthorizationStatus,
        hasShownInitial: Bool
    ) -> Bool {
        recordsSavedLifetime == 1
            && authorizationStatus == .notDetermined
            && !hasShownInitial
    }

    /// The re-ask: at most once, ever, and only once a record's warranty is
    /// genuinely closing in (within 30 days, not yet expired). Never fires
    /// before the initial ask ran, and never once permission is already
    /// decided (accepted or denied) — including mid-flight while the initial
    /// ask itself is still on screen, which callers guard separately.
    nonisolated static func shouldReAsk(
        hasShownInitial: Bool,
        authorizationStatus: UNAuthorizationStatus,
        reAskCount: Int,
        daysUntilNearestWarrantyExpiry: Int?
    ) -> Bool {
        guard hasShownInitial,
              authorizationStatus == .notDetermined,
              reAskCount == 0,
              let days = daysUntilNearestWarrantyExpiry else { return false }
        return (0...30).contains(days)
    }
}

// MARK: - SoftAskCoordinator

/// Drives the N1 soft-ask end to end: decides when to present `SoftAskSheet`
/// over the app root, wires "Yes, notify me" to the real
/// `NotificationManager.requestPermission()`, and handles the single allowed
/// re-ask. Mirrors `ReviewPrompter`'s split — imperative trigger sites report
/// events here; a view modifier attached once at the app root
/// (`softAskPresentation()`) observes `pendingAsk`/`pendingToast` and renders.
///
/// Never presents over an active scan or import: every entry point checks
/// `hasActiveCoverProvider()` (defaults to `AppRouter.shared.hasActiveCover`)
/// before showing anything, so a soft-ask can never interrupt an in-progress
/// `CaptureView` or import-review cover. If a trigger is skipped for that
/// reason, `hasShownInitial` is left `false` so the very next eligible
/// moment (another save, or the foreground re-ask check) can still show it.
@MainActor
@Observable
final class SoftAskCoordinator {
    static let shared = SoftAskCoordinator()

    /// A sheet SwiftUI should render right now. Cleared once the user picks
    /// an option (or, for "Yes", once the system prompt has resolved).
    private(set) var pendingAsk: PendingAsk?
    /// A toast message to show once `pendingAsk` clears. Cleared by the
    /// presenting view via `clearToast()` after it's been consumed.
    private(set) var pendingToast: String?

    struct PendingAsk: Identifiable {
        let id = UUID()
        let itemName: String
        let stakeText: String
    }

    private enum Keys {
        static let recordsSavedLifetime = "softAsk.recordsSavedLifetime"
        static let hasShownInitial = "softAsk.hasShownInitial"
        static let reAskCount = "softAsk.reAskCount"
    }

    private let defaults: UserDefaults
    private let authorizationStatusProvider: () async -> UNAuthorizationStatus
    private let hasActiveCoverProvider: @MainActor () -> Bool

    init(
        defaults: UserDefaults = .standard,
        authorizationStatusProvider: @escaping () async -> UNAuthorizationStatus = {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        },
        hasActiveCoverProvider: @escaping @MainActor () -> Bool = { AppRouter.shared.hasActiveCover }
    ) {
        self.defaults = defaults
        self.authorizationStatusProvider = authorizationStatusProvider
        self.hasActiveCoverProvider = hasActiveCoverProvider
    }

    var recordsSavedLifetime: Int { defaults.integer(forKey: Keys.recordsSavedLifetime) }
    var hasShownInitial: Bool { defaults.bool(forKey: Keys.hasShownInitial) }
    var reAskCount: Int { defaults.integer(forKey: Keys.reAskCount) }

    // MARK: Trigger sites

    /// Call after a successful record save (`DraftRecordView.saveRecord()`),
    /// with the just-saved primary record's product name and warranty date —
    /// shown verbatim in the sample notification banner. Never call from an
    /// error path.
    func recordSaved(count: Int, itemName: String, warrantyExpiryDate: Date?) {
        guard count > 0 else { return }
        defaults.set(recordsSavedLifetime + count, forKey: Keys.recordsSavedLifetime)
        Task { await evaluateInitial(itemName: itemName, warrantyExpiryDate: warrantyExpiryDate) }
    }

    /// The initial-ask evaluation, awaitable directly so tests don't have to
    /// sleep through the settle grace period. `settleGracePeriod` gives an
    /// in-flight cover's dismissal (e.g. `DraftRecordView` closing back to
    /// the app root) a moment to finish before a new sheet rises over it —
    /// mirrors `ReviewPrompter`'s identical 1.5s grace window, for the same
    /// reason: requesting/presenting mid-transition looks broken.
    @discardableResult
    func evaluateInitial(itemName: String, warrantyExpiryDate: Date?, settleGracePeriod: Bool = true) async -> Bool {
        guard pendingAsk == nil, !hasActiveCoverProvider() else { return false }
        let status = await authorizationStatusProvider()
        guard SoftAskEligibility.shouldShowInitial(
            recordsSavedLifetime: recordsSavedLifetime,
            authorizationStatus: status,
            hasShownInitial: hasShownInitial
        ) else { return false }

        if settleGracePeriod {
            try? await Task.sleep(for: .seconds(1.5))
            guard pendingAsk == nil, !hasActiveCoverProvider() else { return false }
        }

        present(itemName: itemName, stakeText: Self.stakeText(warrantyExpiryDate: warrantyExpiryDate), isReAsk: false)
        return true
    }

    /// Cheap, idempotent retry safe to call from any "the app is calm again"
    /// moment — a scan/import cover just closed, or the debounced foreground
    /// refresh. `DraftRecordView.saveRecord()`'s own immediate attempt
    /// (`recordSaved` → `evaluateInitial`) is very often skipped because the
    /// save happens *inside* `CaptureView`, which stays on screen as its own
    /// full-screen cover after `DraftRecordView` pops off its nav stack —
    /// `hasActiveCover` stays true until the user taps CaptureView's own
    /// close button, well past the 1.5s settle window. Without this retry,
    /// `hasShownInitial` would stay false forever and the ask would never
    /// fire for the (most common) scan-flow first save. Once the initial ask
    /// has been shown, this defers to the one allowed re-ask instead.
    @discardableResult
    func retrySoftAsk(records: [PurchaseRecord]) async -> Bool {
        guard pendingAsk == nil, !hasActiveCoverProvider() else { return false }
        guard hasShownInitial else {
            guard let earliest = records.min(by: { $0.createdAt < $1.createdAt }) else { return false }
            // Grace period on: a cover-close transition still has its own
            // dismiss animation playing when this fires; give it the same
            // 1.5s settle window as the save-time attempt.
            return await evaluateInitial(itemName: earliest.productName, warrantyExpiryDate: earliest.warrantyExpiryDate)
        }
        return await checkReAsk(records: records)
    }

    /// Re-ask predicate in isolation — at most once ever, only once some
    /// record's warranty is genuinely closing in and permission is still
    /// undetermined. Prefer `retrySoftAsk` at real call sites; this is
    /// exposed directly for focused testing.
    @discardableResult
    func checkReAsk(records: [PurchaseRecord]) async -> Bool {
        guard pendingAsk == nil, !hasActiveCoverProvider() else { return false }
        guard let nearest = Self.nearestExpiring(records: records) else { return false }

        let status = await authorizationStatusProvider()
        guard SoftAskEligibility.shouldReAsk(
            hasShownInitial: hasShownInitial,
            authorizationStatus: status,
            reAskCount: reAskCount,
            daysUntilNearestWarrantyExpiry: nearest.days
        ) else { return false }

        present(itemName: nearest.record.productName, stakeText: Self.stakeText(warrantyExpiryDate: nearest.record.warrantyExpiryDate), isReAsk: true)
        return true
    }

    // MARK: Responses

    /// "Yes, notify me" — request the real system prompt, then (either
    /// outcome) toast and dismiss together, per ANIMATION_SPEC §6.
    func respondYes() {
        Task {
            let granted = await NotificationManager.shared.requestPermission()
            pendingAsk = nil
            pendingToast = granted
                ? "You're set — we'll only knock once, right before it matters."
                : "No worries — turn this on anytime from Settings."
        }
    }

    /// "NOT NOW" — dismiss without a system prompt. No decline flag beyond
    /// `hasShownInitial`/`reAskCount` is needed: eligibility for the re-ask is
    /// already fully gated by `authorizationStatus` staying `.notDetermined`,
    /// which is exactly the state "declined" leaves it in.
    func respondNotNow() {
        pendingAsk = nil
        AppLogger.info("Soft-ask declined", category: "notifications")
    }

    func clearToast() {
        pendingToast = nil
    }

    // MARK: Helpers

    private func present(itemName: String, stakeText: String, isReAsk: Bool) {
        defaults.set(true, forKey: Keys.hasShownInitial)
        if isReAsk {
            defaults.set(reAskCount + 1, forKey: Keys.reAskCount)
        }
        pendingAsk = PendingAsk(itemName: itemName, stakeText: stakeText)
        AppLogger.info("Soft-ask presented (reAsk: \(isReAsk))", category: "notifications")
    }

    /// The nearest not-yet-expired warranty within the next 30 days, if any —
    /// the real record the re-ask's sample banner shows. `nonisolated`: pure
    /// date math over the records passed in, no `SoftAskCoordinator` state —
    /// same reasoning as `SoftAskEligibility`, and needed so tests can call
    /// it from non-`@MainActor` contexts.
    nonisolated static func nearestExpiring(records: [PurchaseRecord], now: Date = .now) -> (record: PurchaseRecord, days: Int)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return records
            .compactMap { record -> (record: PurchaseRecord, days: Int)? in
                guard let expiry = record.warrantyExpiryDate,
                      let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: expiry)).day
                else { return nil }
                return (record, days)
            }
            .filter { (0...30).contains($0.days) }
            .min { $0.days < $1.days }
    }

    private static func stakeText(warrantyExpiryDate: Date?) -> String {
        guard let warrantyExpiryDate else {
            return "One quiet note, right before it matters. Nothing else, ever."
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return "Warranty ends \(formatter.string(from: warrantyExpiryDate)). Your proof is ready if you need it."
    }
}

// MARK: - App-root presentation

/// Attach once, at the app root, so the paper sheet rises over the dimmed
/// app and the toast lands in the same place every other `ptToast` does.
/// DESIGN_LANGUAGE.md §5/§9, ANIMATION_SPEC.md §6: dim 0→.72, sheet rises
/// 420ms `sheetEase`; Reduce Motion collapses both to a 200ms crossfade.
private struct SoftAskPresentationModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var coordinator = SoftAskCoordinator.shared
    @State private var toast: PTToastItem?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let ask = coordinator.pendingAsk {
                    ZStack {
                        Color.black.opacity(0.72)
                            .ignoresSafeArea()
                            .transition(.opacity)

                        SoftAskSheet(
                            itemName: ask.itemName,
                            stakeText: ask.stakeText,
                            onYes: { coordinator.respondYes() },
                            onNotNow: { coordinator.respondNotNow() }
                        )
                        .padding(14)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                    .accessibilityAddTraits(.isModal)
                    .zIndex(100)
                }
            }
            .animation(PTMotion.reduced(PTMotion.sheetEase(0.42), reduceMotion: reduceMotion), value: coordinator.pendingAsk?.id)
            .onChange(of: coordinator.pendingToast) { _, message in
                guard let message else { return }
                toast = PTToastItem(message: message)
                coordinator.clearToast()
            }
            .ptToast($toast)
    }
}

extension View {
    /// Presents the N1 soft-ask sheet whenever `SoftAskCoordinator.shared`
    /// has something pending. Attach once, at the app root (`AppShellView`).
    func softAskPresentation() -> some View {
        modifier(SoftAskPresentationModifier())
    }
}
