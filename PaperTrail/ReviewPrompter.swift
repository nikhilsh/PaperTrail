import SwiftUI
import StoreKit

/// Pure eligibility rule for the App Store review prompt. Kept `nonisolated`
/// so it's a plain, synchronous, fully-testable function — the app target
/// builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would
/// otherwise pin this to the main actor for no reason.
enum ReviewEligibility {
    nonisolated static func shouldPrompt(
        recordsSavedLifetime: Int,
        isFirstSession: Bool,
        lastPromptedVersion: String?,
        currentVersion: String?
    ) -> Bool {
        guard !isFirstSession else { return false }
        guard recordsSavedLifetime >= 5 else { return false }
        guard let currentVersion, !currentVersion.isEmpty else { return false }
        if lastPromptedVersion == currentVersion { return false }
        return true
    }
}

/// Tracks eligibility for StoreKit's review prompt and publishes a
/// "should prompt" signal for the app-root modifier to act on.
///
/// Trigger sites are imperative (a save completing, a PDF finishing), but
/// `requestReview` is only reachable as a SwiftUI `@Environment` action, so
/// this splits the two: call sites report delight moments here, and
/// `reviewPrompting()` (attached once at the app root) observes `shouldPrompt`
/// and performs the actual request.
@MainActor
@Observable
final class ReviewPrompter {
    static let shared = ReviewPrompter()

    private enum Keys {
        static let recordsSavedLifetime = "reviewPrompt.recordsSavedLifetime"
        static let hasLaunchedBefore = "reviewPrompt.hasLaunchedBefore"
        static let lastPromptedVersion = "reviewPrompt.lastPromptedVersion"
    }

    /// Set true once a delight moment makes the user eligible; the app-root
    /// modifier observes this, requests the review, and clears it.
    private(set) var shouldPrompt = false

    private let defaults: UserDefaults
    /// Captured once at init (i.e. once per app launch/session) — never
    /// prompt during the very first session the app is ever run.
    private let isFirstSession: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.hasLaunchedBefore: false])
        isFirstSession = !defaults.bool(forKey: Keys.hasLaunchedBefore)
        defaults.set(true, forKey: Keys.hasLaunchedBefore)
    }

    private var recordsSavedLifetime: Int {
        defaults.integer(forKey: Keys.recordsSavedLifetime)
    }

    private var lastPromptedVersion: String? {
        defaults.string(forKey: Keys.lastPromptedVersion)
    }

    private var currentAppVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Call after a successful scan→save completes, with the number of
    /// records just saved. Never call this from an error path.
    func recordsSaved(_ count: Int) {
        guard count > 0 else { return }
        defaults.set(recordsSavedLifetime + count, forKey: Keys.recordsSavedLifetime)
        evaluate()
    }

    /// Call after a claim-packet PDF export completes successfully. Never
    /// call this from an error path.
    func claimPacketExported() {
        evaluate()
    }

    private func evaluate() {
        guard !shouldPrompt else { return }
        guard ReviewEligibility.shouldPrompt(
            recordsSavedLifetime: recordsSavedLifetime,
            isFirstSession: isFirstSession,
            lastPromptedVersion: lastPromptedVersion,
            currentVersion: currentAppVersion
        ) else { return }
        shouldPrompt = true
    }

    /// Called by `reviewPrompting()` right after it invokes StoreKit's
    /// `requestReview` action, so we never ask twice in the same version.
    func didPrompt() {
        shouldPrompt = false
        if let currentAppVersion {
            defaults.set(currentAppVersion, forKey: Keys.lastPromptedVersion)
        }
        AppLogger.info("Requested App Store review prompt", category: "review")
    }
}

/// App-root modifier: observes `ReviewPrompter`'s signal and performs the
/// actual StoreKit review request, which is only available as a SwiftUI
/// environment action (not callable from the imperative trigger sites).
private struct ReviewPromptModifier: ViewModifier {
    @Environment(\.requestReview) private var requestReview
    private var prompter = ReviewPrompter.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: prompter.shouldPrompt) { _, shouldPrompt in
                guard shouldPrompt else { return }
                Task {
                    // A delight moment (save/export) often fires right as a
                    // full-screen cover is dismissing; StoreKit silently
                    // suppresses the prompt if it's requested mid-transition.
                    // Give the dismissal a moment to settle first — we still
                    // burn the once-per-version budget either way.
                    try? await Task.sleep(for: .seconds(1.5))
                    requestReview()
                    prompter.didPrompt()
                }
            }
    }
}

extension View {
    /// Attach once, at the app root, so `requestReview()` is called from a
    /// stable, always-mounted view.
    func reviewPrompting() -> some View {
        modifier(ReviewPromptModifier())
    }
}
