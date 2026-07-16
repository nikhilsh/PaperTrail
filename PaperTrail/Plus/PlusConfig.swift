import Foundation

/// Static configuration for "PaperTrail Plus" (StoreKit 2 subscriptions) — see
/// docs/MONETIZATION.md for the pricing/copy spec of record.
///
/// `enabled` is the single master switch: while `false`, nothing Plus-related
/// is visible or active anywhere in the app (no paywall entry points, no
/// StoreKit calls, no gates) — the store build stays byte-identical to today.
/// App Store Connect doesn't have these products yet, so this MUST stay
/// `false` until they're created and this has been verified end-to-end.
enum PlusConfig {

    /// Master switch. Flip only after ASC products exist and StoreKit
    /// integration has been verified on-device.
    static let enabled = false

    /// StoreKit product identifiers (App Store Connect: subscription group
    /// "PaperTrail Plus" for the two subscriptions, non-consumable for lifetime).
    enum ProductID {
        static let monthly = "plus.monthly"
        static let yearly = "plus.yearly"
        static let lifetime = "plus.lifetime"

        static let all = [monthly, yearly, lifetime]
    }

    /// The free-forever promise (docs/MONETIZATION.md "The principle") — shown
    /// on the paywall itself, deliberately first, as a trust move: show what
    /// you're NOT paying for before asking for money.
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

    /// The three payoff moments Plus unlocks (docs/MONETIZATION.md "Paid").
    static let benefits: [Benefit] = [
        Benefit(icon: "person.2.fill",
                title: "Unlimited household sharing",
                subtitle: "Share with everyone at home, not just one member"),
        Benefit(icon: "house.fill",
                title: "Whole-home insurance report",
                subtitle: "Every room, not just one — the artifact you hand an insurer"),
        Benefit(icon: "calendar.badge.clock",
                title: "Priority digest features",
                subtitle: "Warranty Digest Pro — money-saved summaries & defect nudges")
    ]
}
