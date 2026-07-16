import Testing
import Foundation
@testable import PaperTrail

/// Pure date-math tests for `RenewalReminder.triggerDate` — 14 days before
/// the membership's `expirationDate`, `nil` once that trigger moment has
/// already passed. No `UNUserNotificationCenter` access here; that requires
/// a device/simulator with notification entitlements (mirrors
/// `NotificationIdentifierTests`'s scope).
struct RenewalReminderTests {

    private let calendar = Calendar(identifier: .gregorian)

    @Test func fourteenDaysBeforeExpiration() {
        let now = date("2026-07-01")
        let expiration = date("2026-07-30")
        let trigger = RenewalReminder.triggerDate(expirationDate: expiration, now: now, calendar: calendar)
        let expected = calendar.date(byAdding: .day, value: -14, to: expiration)!
        #expect(trigger != nil)
        #expect(calendar.isDate(trigger!, inSameDayAs: expected))
    }

    @Test func triggerTooCloseToNowSchedulesNothing() {
        // 14 days before a 5-day-out expiration is already in the past.
        let now = date("2026-07-25")
        let expiration = date("2026-07-30")
        #expect(RenewalReminder.triggerDate(expirationDate: expiration, now: now, calendar: calendar) == nil)
    }

    @Test func expirationAlreadyInThePastSchedulesNothing() {
        let now = date("2026-08-01")
        let expiration = date("2026-07-01")
        #expect(RenewalReminder.triggerDate(expirationDate: expiration, now: now, calendar: calendar) == nil)
    }

    @Test func triggerExactlyNowSchedulesNothing() {
        // Boundary: the candidate trigger date equals `now` — not strictly
        // in the future, so it doesn't schedule (avoids a same-instant race
        // with UNCalendarNotificationTrigger).
        let expiration = date("2026-07-15")
        let now = calendar.date(byAdding: .day, value: -14, to: expiration)!
        #expect(RenewalReminder.triggerDate(expirationDate: expiration, now: now, calendar: calendar) == nil)
    }

    @Test func comfortablyFutureExpirationSchedules() {
        let now = date("2026-01-01")
        let expiration = date("2027-01-01")
        #expect(RenewalReminder.triggerDate(expirationDate: expiration, now: now, calendar: calendar) != nil)
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }
}
