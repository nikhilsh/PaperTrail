import Foundation
import UserNotifications

/// The single "your membership renews soon" local notification — annual
/// plan only (docs/design-v2/V2_BRIEF.md §4, DESIGN_LANGUAGE.md §7: "Renewal
/// reminder is a REAL notification (counts toward the 2/month cap in its
/// month)"). Exactly one pending request ever, identifier "plus-renewal" —
/// rescheduled from scratch whenever `PlusEntitlements` refreshes its
/// entitlement, removed outright on lapse or for the monthly plan (the point
/// is the once-a-year moment, not a recurring nag).
///
/// Mirrors `DigestScheduler`'s shape: a single named identifier, cleared and
/// re-added every call rather than diffed, so it's always in sync with the
/// live entitlement instead of drifting stale between refreshes.
enum RenewalReminder {
    static let identifier = "plus-renewal"

    /// 14 days before `expirationDate` — `nil` if that's already in the past
    /// (or exactly now), so a stale/near-term expiration never schedules a
    /// notification for a moment that's already gone. Pure date math, no
    /// `UNUserNotificationCenter` involved — testable without a device.
    nonisolated static func triggerDate(expirationDate: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let candidate = calendar.date(byAdding: .day, value: -14, to: expirationDate) else { return nil }
        return candidate > now ? candidate : nil
    }

    /// Reschedules the annual renewal reminder for `expirationDate`, quoting
    /// `priceText` (a pre-formatted, live StoreKit `displayPrice`, e.g.
    /// "S$29.98"). Always clears any previous request first, so this is
    /// safe — and idempotent — to call on every entitlement refresh; if
    /// `triggerDate` says it's too late, nothing gets re-added.
    static func scheduleAnnual(expirationDate: Date, priceText: String, now: Date = .now, calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard let triggerDate = triggerDate(expirationDate: expirationDate, now: now, calendar: calendar) else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"

        let content = UNMutableNotificationContent()
        content.title = "Your PaperTrail membership"
        content.body = "Renews on \(dateFormatter.string(from: expirationDate)) — \(priceText). Cancel anytime keeps everything."
        content.sound = .default
        content.categoryIdentifier = "PLUS_RENEWAL"

        let components = calendar.dateComponents([.year, .month, .day, .hour], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                AppLogger.error("Failed to schedule Plus renewal reminder: \(error.localizedDescription)", category: "plus")
            }
        }
    }

    /// Removes the reminder outright — lapsed membership, monthly plan, or
    /// no active entitlement at all.
    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
