import Foundation

/// Static configuration for "PaperTrail Plus" (StoreKit 2 subscriptions) — see
/// docs/MONETIZATION.md for the pricing/copy spec of record.
///
/// `enabled` is the single master switch: while `false`, nothing Plus-related
/// is visible or active anywhere in the app (no paywall entry points, no
/// StoreKit calls, no gates) — the store build stays byte-identical to today.
/// `true` now that App Store Connect sandbox products exist — see `enabled`'s
/// doc comment for current status and what still needs re-checking before
/// a real App Store submission.
enum PlusConfig {

    /// Master switch. Flip only after ASC products exist and StoreKit
    /// integration has been verified on-device.
    ///
    /// `true` for the build-36 IAP debug pass: ASC sandbox products exist
    /// (plus.monthly, plus.yearly, plus.lifetime) and this needs on-device
    /// verification via `PlusDebugView`. MUST be re-evaluated before any
    /// App Store submission — flip back to `false` if Plus isn't ready to
    /// launch publicly yet.
    static let enabled = true

    /// Master switch for the in-app "Plus Debug" console (`PlusDebugView`),
    /// reachable from Advanced & Diagnostics. It exposes raw StoreKit state,
    /// direct buy buttons, and a local entitlement override that bypasses
    /// payment entirely — there is NO Xcode/Transaction Manager on the dev
    /// box, so the app itself has to carry this tooling for sandbox testing
    /// on Ad Hoc OTA builds.
    ///
    /// ⚠️ MUST NEVER SHIP TO THE APP STORE. This is a debug-only escape
    /// hatch (entitlement override, raw transaction dump) that has no
    /// business in a production build. Compile-time gated on the
    /// `APPSTORE` build flag (set for the App Store release configuration)
    /// rather than a plain `Bool` constant — a stray `true` can no longer
    /// slip into a store submission, since it's not something a future edit
    /// to this line can silently override for that configuration.
    static let debugConsoleEnabled: Bool = {
        #if APPSTORE
        false
        #else
        true
        #endif
    }()

    /// StoreKit product identifiers (App Store Connect: subscription group
    /// "PaperTrail Plus" for the two subscriptions, non-consumable for lifetime).
    enum ProductID {
        static let monthly = "plus.monthly"
        static let yearly = "plus.yearly"
        static let lifetime = "plus.lifetime"

        /// Every product ID recognized for *entitlement* purposes — a past
        /// lifetime purchase still grants Plus (legacy support), and the
        /// debug console still needs to buy/inspect it. NOT the paywall's
        /// plan list — see `subscriptionPlans`.
        static let all = [monthly, yearly, lifetime]

        /// The two plans the paywall actually sells (v2.1,
        /// docs/design-v2/DESIGN_LANGUAGE.md §7: "Two plans max... No
        /// lifetime tier"). Annual first — it's the default-selected plan.
        static let subscriptionPlans = [yearly, monthly]
    }

    /// The free-forever promise (docs/MONETIZATION.md "The principle") — the
    /// trust move behind "Cancel keeps everything" on the v2.1 certificate
    /// paywall (`PaywallView`), which doesn't spell out this list directly
    /// but is built on the same premise: nothing here is ever held hostage.
    static let freeForever: [String] = [
        "Unlimited scanning, OCR, and AI extraction",
        "Unlimited records and private iCloud storage",
        "Export everything — PDF + CSV, no lock-in",
        "Warranty & return-window reminders",
        "No account, no email, no tracking"
    ]

    /// A single Plus benefit for paywall display.
    struct Benefit {
        let icon: String
        let title: String
        let subtitle: String
    }

    /// The payoff moments Plus unlocks (docs/MONETIZATION.md "Paid" +
    /// docs/design-v2/V2_BRIEF.md §3: the certificate shows exactly four
    /// benefit checks). `title` doubles as the certificate's checkmark copy
    /// (`CertificateView(benefits: PlusConfig.benefits.map(\.title))`).
    static let benefits: [Benefit] = [
        Benefit(icon: "person.2.fill",
                title: "Unlimited household sharing",
                subtitle: "Share with everyone at home, not just one member"),
        Benefit(icon: "house.fill",
                title: "Whole-home insurance report",
                subtitle: "Every room, not just one — the artifact you hand an insurer"),
        Benefit(icon: "calendar.badge.clock",
                title: "Priority digest features",
                subtitle: "Warranty Digest Pro — money-saved summaries & defect nudges"),
        Benefit(icon: "sparkles",
                title: "Every future Plus feature",
                subtitle: "Included automatically — nothing more to buy")
    ]
}
