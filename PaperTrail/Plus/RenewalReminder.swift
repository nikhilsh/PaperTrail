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

    /// The trial-ending reminder's identifier — kept separate from
    /// `identifier` so scheduling one never clobbers (or is clobbered by)
    /// the other; `PlusEntitlements.updateRenewalReminder` only ever keeps
    /// one of the two live for a given entitlement, cancelling the other.
    static let trialEndingIdentifier = "plus-trial-ending"

    /// 14 days before `expirationDate` — `nil` if that's already in the past
    /// (or exactly now), so a stale/near-term expiration never schedules a
    /// notification for a moment that's already gone. Pure date math, no
    /// `UNUserNotificationCenter` involved — testable without a device.
    nonisolated static func triggerDate(expirationDate: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let candidate = calendar.date(byAdding: .day, value: -14, to: expirationDate) else { return nil }
        return candidate > now ? candidate : nil
    }

    /// 3 days before `expirationDate` (the trial's own bill date) — `nil` if
    /// that's already in the past (or exactly now). Shorter lead than the
    /// 14-day annual reminder because the whole intro trial is only 14 days
    /// long, so a 14-day-out reminder would land before — or right at — the
    /// trial's own start. Pure date math, testable without a device.
    nonisolated static func trialEndingTriggerDate(expirationDate: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let candidate = calendar.date(byAdding: .day, value: -3, to: expirationDate) else { return nil }
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

    /// Reschedules the trial-ending reminder for `expirationDate` (the
    /// intro trial's own bill date), quoting `priceText` — the price that
    /// applies once the trial converts. Always clears any previous request
    /// first, so this is safe — and idempotent — to call on every
    /// entitlement refresh; if `trialEndingTriggerDate` says it's too late,
    /// nothing gets re-added.
    static func scheduleTrialEnding(expirationDate: Date, priceText: String, now: Date = .now, calendar: Calendar = .current) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [trialEndingIdentifier])

        guard let triggerDate = trialEndingTriggerDate(expirationDate: expirationDate, now: now, calendar: calendar) else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"

        let content = UNMutableNotificationContent()
        content.title = "Your PaperTrail membership"
        content.body = "Your free fortnight ends \(dateFormatter.string(from: expirationDate)) — \(priceText)/yr after."
        content.sound = .default
        content.categoryIdentifier = "PLUS_RENEWAL"

        let components = calendar.dateComponents([.year, .month, .day, .hour], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: trialEndingIdentifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                AppLogger.error("Failed to schedule Plus trial-ending reminder: \(error.localizedDescription)", category: "plus")
            }
        }
    }

    /// Removes the trial-ending reminder outright — trial converted to a
    /// paid period, lapsed, or switched to monthly/lifetime.
    static func cancelTrialEnding() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [trialEndingIdentifier])
    }
}
