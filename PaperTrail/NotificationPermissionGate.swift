import SwiftUI
import UIKit
import SwiftData
import UserNotifications

// MARK: - AskContext

/// Which notification-producing feature is asking. Carries the copy the ask
/// sheet and DENIED sheet render — one funnel (`NotificationPermissionGate`)
/// instead of every toggle rolling its own permission dance. `.warranty`
/// covers both warranty AND return-window reminders: the original N1
/// soft-ask copy already bundles them ("before a warranty or return window
/// closes"), so a separate return-window context would just repeat it.
nonisolated enum AskContext: String, Equatable {
    case warranty
    case digest
    case coverage
    /// Not routed through `ensurePermission` — `RecallWatcher` is cap-exempt
    /// and always schedules its safety notification regardless of
    /// authorization (see `RecallWatcher.scheduleSafetyNotification`). This
    /// case exists only so the recall status row's honest line can
    /// re-present the DENIED sheet via `presentDeniedDirectly`.
    case recall

    var kicker: String {
        switch self {
        case .warranty, .coverage, .recall: "BEFORE YOU PUT THIS AWAY"
        case .digest: "ONE NOTE A MONTH"
        }
    }

    var title: String {
        switch self {
        case .warranty, .coverage, .recall: "May we leave a note?"
        case .digest: "A monthly once-over?"
        }
    }

    var bodyText: String {
        switch self {
        case .warranty, .coverage, .recall:
            "One quiet heads-up before a warranty or return window closes. That's the only reason we'll ever knock. No marketing, ever."
        case .digest:
            "One summary a month of what's expiring and what's closing. That's the only reason we'll ever knock. No marketing, ever."
        }
    }

    /// The ask sheet's sample-notification banner title.
    var sampleTitle: String {
        switch self {
        case .warranty, .coverage, .recall: "Samsung TV — 2 weeks left"
        case .digest: "Your coverage this month"
        }
    }

    /// The ask sheet's sample-notification banner body.
    var sampleBody: String {
        switch self {
        case .warranty, .coverage, .recall: "Warranty ends 3 Jun. Your proof is ready if you need it."
        case .digest: "3 warranties closing in, 1 return window open."
        }
    }

    /// DENIED sheet body — names what the user just tried to turn on, per
    /// item 3's "no shame, no nagging" brief.
    var deniedBody: String {
        switch self {
        case .warranty: "Warranty reminders need iOS permission to reach you."
        case .digest: "The monthly digest needs iOS permission to reach you."
        case .coverage: "Coverage reminders need iOS permission to reach you."
        case .recall: "Safety recall alerts need iOS permission to reach you."
        }
    }
}

// MARK: - NotificationPermissionDecision (pure, testable)

/// Pure status → outcome mapping, pulled out of `NotificationPermissionGate`
/// the same way `SoftAskEligibility` is pulled out of `SoftAskCoordinator` —
/// fully testable without `UNUserNotificationCenter` or any UI.
nonisolated enum NotificationPermissionDecision: Equatable {
    /// Already authorized (or provisional/ephemeral) — proceed immediately,
    /// no sheet.
    case proceed
    /// Undetermined — show the ask sheet before the real system prompt.
    case ask
    /// Denied — show the DENIED sheet pointing at iOS Settings. Never calls
    /// `requestAuthorization` again; iOS silently no-ops a repeat request
    /// once denied, so there's nothing to ask for.
    case denied

    nonisolated static func decision(for status: UNAuthorizationStatus) -> NotificationPermissionDecision {
        switch status {
        case .authorized, .provisional, .ephemeral: .proceed
        case .notDetermined: .ask
        case .denied: .denied
        @unknown default: .denied
        }
    }
}

// MARK: - NotificationPermissionGate

/// Single funnel every notification-producing toggle/feature goes through
/// before relying on a local notification actually reaching the user.
/// Mirrors `SoftAskCoordinator`'s coordinator+overlay idiom: imperative call
/// sites call `ensurePermission(context:)`; a view modifier attached once at
/// the app root (`notificationPermissionPresentation()`) observes
/// `pendingAsk`/`pendingDenied` and renders.
///
/// Unlike the N1 soft-ask (which only ever fires once, at first save),
/// this gate can be invoked repeatedly — every reminder toggle flip, every
/// tap on an "off in Settings" honest row — so it carries no once-ever
/// budget of its own; presenting the DENIED sheet is always a direct
/// response to a direct user action, never unprompted.
@MainActor
@Observable
final class NotificationPermissionGate {
    static let shared = NotificationPermissionGate()

    private(set) var pendingAsk: PendingAsk?
    private(set) var pendingDenied: PendingDenied?

    /// Last observed authorization status, persisted so honest rows (a
    /// reminder toggle left ON while denied, the recall status row) can
    /// render correctly on next launch without an extra async round trip,
    /// and so `reArmIfNeeded` can detect a denied→authorized transition
    /// across a cold relaunch (the user backgrounded the app, flipped the
    /// toggle in Settings, and force-quit rather than switching back).
    private(set) var lastKnownAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    struct PendingAsk: Identifiable {
        let id = UUID()
        let context: AskContext
    }

    struct PendingDenied: Identifiable {
        let id = UUID()
        let context: AskContext
    }

    private enum Keys {
        static let lastKnownStatus = "notificationPermissionGate.lastKnownStatus"
    }

    private let defaults: UserDefaults
    private let authorizationStatusProvider: () async -> UNAuthorizationStatus
    private let modelContextProvider: @MainActor () -> ModelContext

    /// Resumed by `respondYes`/`respondNotNow` — the single in-flight ask's
    /// continuation. `ensurePermission` suspends on this while `.ask` is
    /// pending, same shape as `SoftAskCoordinator`'s single-flight
    /// `isCheckingReAsk` guard but via `withCheckedContinuation` since the
    /// caller here needs the actual grant/decline result back.
    private var askContinuation: CheckedContinuation<Bool, Never>?

    init(
        defaults: UserDefaults = .standard,
        authorizationStatusProvider: @escaping () async -> UNAuthorizationStatus = {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        },
        modelContextProvider: @escaping @MainActor () -> ModelContext = { PaperTrailModelContainer.shared.mainContext }
    ) {
        self.defaults = defaults
        self.authorizationStatusProvider = authorizationStatusProvider
        self.modelContextProvider = modelContextProvider
        if defaults.object(forKey: Keys.lastKnownStatus) != nil {
            lastKnownAuthorizationStatus = UNAuthorizationStatus(rawValue: defaults.integer(forKey: Keys.lastKnownStatus)) ?? .notDetermined
        }
    }

    // MARK: Entry point

    /// The single funnel every notification-producing feature calls before
    /// relying on a local notification reaching the user. Resolves
    /// immediately when already decided; suspends on the ask sheet when
    /// undetermined; presents (and returns `false` from) the DENIED sheet
    /// when denied.
    @discardableResult
    func ensurePermission(context: AskContext) async -> Bool {
        let status = await authorizationStatusProvider()
        recordStatus(status)
        AppLogger.info("Notification gate invoked (context: \(context.rawValue), status: \(status.logName))", category: "notifications")

        switch NotificationPermissionDecision.decision(for: status) {
        case .proceed:
            return true
        case .ask:
            return await presentAsk(context: context)
        case .denied:
            presentDenied(context: context)
            return false
        }
    }

    // MARK: Ask sheet

    private func presentAsk(context: AskContext) async -> Bool {
        guard pendingAsk == nil else { return false }
        return await withCheckedContinuation { continuation in
            askContinuation = continuation
            pendingAsk = PendingAsk(context: context)
            AppLogger.info("Ask sheet shown (context: \(context.rawValue))", category: "notifications")
        }
    }

    /// "Yes, notify me" — request the real system prompt, then (on grant)
    /// re-arm every reminder type so anything scheduled-but-suppressed
    /// before this moment actually fires.
    func respondYes(context: AskContext) {
        pendingAsk = nil
        Task {
            let granted = await NotificationManager.shared.requestPermission()
            AppLogger.info("System prompt result: \(granted) (context: \(context.rawValue))", category: "notifications")
            let status = await authorizationStatusProvider()
            recordStatus(status)
            if granted {
                let modelContext = modelContextProvider()
                await NotificationManager.shared.rescheduleAll(modelContext: modelContext)
                DigestScheduler.reschedule(modelContext: modelContext)
            }
            askContinuation?.resume(returning: granted)
            askContinuation = nil
        }
    }

    /// "NOT NOW" — dismiss without a system prompt.
    func respondNotNow() {
        pendingAsk = nil
        AppLogger.info("Ask sheet declined", category: "notifications")
        askContinuation?.resume(returning: false)
        askContinuation = nil
    }

    // MARK: Denied sheet

    private func presentDenied(context: AskContext) {
        pendingDenied = PendingDenied(context: context)
        AppLogger.info("Denied sheet shown (context: \(context.rawValue))", category: "notifications")
    }

    /// Re-presents the DENIED sheet for a feature that isn't gated by
    /// `ensurePermission` directly — a tap on an honest row that's already
    /// showing "off in Settings" (a reminder toggle, or the recall status
    /// row). One sheet per tap; never auto-repeats.
    func presentDeniedDirectly(context: AskContext) {
        presentDenied(context: context)
    }

    func dismissDenied() {
        pendingDenied = nil
    }

    /// "Open iOS Settings" — deep-links straight to PaperTrail's
    /// notification settings when available (iOS 15.4+), else the app's
    /// general Settings page. Mirrors `VoiceCaptureSheet.blockedContent`'s
    /// shape (`AddSheetView.swift`).
    func openNotificationSettings() {
        AppLogger.info("Settings deeplink tapped", category: "notifications")
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) ?? URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        pendingDenied = nil
    }

    // MARK: Re-arm on return from Settings

    /// Called from the debounced foreground hook (`ForegroundRefreshCoordinator`
    /// in `AppShellView.swift`). Detects a denied/undetermined → authorized
    /// transition (the user granted permission in Settings and came back)
    /// and re-arms every reminder type, since nothing else does once
    /// permission actually lands. No-ops on the very first observation ever
    /// (nothing to compare against yet — would otherwise fire a spurious
    /// reschedule for every already-authorized user on first launch after
    /// this feature ships) and whenever status hasn't changed.
    @discardableResult
    func reArmIfNeeded() async -> Bool {
        let isFirstObservation = defaults.object(forKey: Keys.lastKnownStatus) == nil
        let previous = lastKnownAuthorizationStatus
        let current = await authorizationStatusProvider()
        recordStatus(current)

        guard !isFirstObservation, previous != current else { return false }

        let wasBlocked = previous == .denied || previous == .notDetermined
        let nowAuthorized = current == .authorized || current == .provisional || current == .ephemeral
        guard wasBlocked, nowAuthorized else { return false }

        AppLogger.info(
            "Notification authorization transitioned \(previous.logName) -> \(current.logName); re-arming reminders",
            category: "notifications"
        )
        let modelContext = modelContextProvider()
        await NotificationManager.shared.rescheduleAll(modelContext: modelContext)
        DigestScheduler.reschedule(modelContext: modelContext)
        return true
    }

    /// Refreshes `lastKnownAuthorizationStatus` without any presentation or
    /// re-arm side effect — called from honest-row views on appear so their
    /// "off in Settings" line reflects the real current status rather than
    /// whatever was last observed at launch or the last foreground.
    func refreshAuthorizationStatus() async {
        let status = await authorizationStatusProvider()
        recordStatus(status)
    }

    private func recordStatus(_ status: UNAuthorizationStatus) {
        lastKnownAuthorizationStatus = status
        defaults.set(status.rawValue, forKey: Keys.lastKnownStatus)
    }
}

private extension UNAuthorizationStatus {
    var logName: String {
        switch self {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }
}

// MARK: - App-root presentation

/// Attach once, at the app root, alongside `softAskPresentation()`. Same
/// dim/rise choreography as `SoftAskSheet` (ANIMATION_SPEC.md §6): dim
/// 0→.72, sheet rises 420ms `sheetEase`; Reduce Motion collapses to a 200ms
/// crossfade. `pendingAsk` and `pendingDenied` are never both set at once —
/// `ensurePermission` only ever presents one or the other for a given call.
private struct NotificationPermissionPresentationModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var gate = NotificationPermissionGate.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if let ask = gate.pendingAsk {
                    ZStack {
                        Color.black.opacity(0.72)
                            .ignoresSafeArea()
                            .transition(.opacity)

                        SoftAskSheet(
                            itemName: ask.context.sampleTitle,
                            stakeText: ask.context.sampleBody,
                            kicker: ask.context.kicker,
                            title: ask.context.title,
                            bodyText: ask.context.bodyText,
                            onYes: { gate.respondYes(context: ask.context) },
                            onNotNow: { gate.respondNotNow() }
                        )
                        .padding(14)
                        .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    .accessibilityAddTraits(.isModal)
                    .zIndex(100)
                } else if let denied = gate.pendingDenied {
                    ZStack {
                        Color.black.opacity(0.72)
                            .ignoresSafeArea()
                            .transition(.opacity)

                        NotificationDeniedSheet(
                            context: denied.context,
                            onOpenSettings: { gate.openNotificationSettings() },
                            onNotNow: { gate.dismissDenied() }
                        )
                        .padding(14)
                        .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    .accessibilityAddTraits(.isModal)
                    .zIndex(100)
                }
            }
            .animation(PTMotion.reduced(PTMotion.sheetEase(0.42), reduceMotion: reduceMotion), value: gate.pendingAsk?.id)
            .animation(PTMotion.reduced(PTMotion.sheetEase(0.42), reduceMotion: reduceMotion), value: gate.pendingDenied?.id)
    }
}

extension View {
    /// Presents the notification-permission ask/DENIED sheets whenever
    /// `NotificationPermissionGate.shared` has something pending. Attach
    /// once, at the app root (`AppShellView`).
    func notificationPermissionPresentation() -> some View {
        modifier(NotificationPermissionPresentationModifier())
    }
}
