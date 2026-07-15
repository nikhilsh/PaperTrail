import Foundation
import SwiftData
import UserNotifications

/// Reschedules the single "monthly coverage digest" local notification on
/// every app foreground, so it's always built from live data instead of
/// drifting stale between launches. Only ever one pending request —
/// identifier `notificationIdentifier` — recomputed and re-added each time
/// (or removed outright when there's nothing worth telling the user, or the
/// toggle is off).
@MainActor
enum DigestScheduler {
    static let notificationIdentifier = "monthly-digest"

    /// Call from app-foreground, alongside the Spotlight reindex hook in
    /// `AppShellView`.
    static func reschedule(modelContext: ModelContext) {
        let center = UNUserNotificationCenter.current()

        guard ReminderSettings.shared.digestEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            return
        }

        let summary = buildSummary(modelContext: modelContext)
        guard !summary.isEmpty else {
            center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            AppLogger.info("Digest empty — nothing to schedule", category: "digest")
            return
        }

        guard let triggerDate = nextFirstOfMonth9AM() else {
            AppLogger.error("Failed to compute next digest trigger date", category: "digest")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Your coverage this month"
        content.body = summary.headline
        content.sound = .default
        content.userInfo = ["route": "expiringSoon"]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.add(request) { error in
            if let error {
                AppLogger.error("Failed to schedule monthly digest: \(error.localizedDescription)", category: "digest")
            } else {
                AppLogger.info("Scheduled monthly digest", category: "digest")
            }
        }
    }

    /// Fetches every record and reduces it to a `DigestSummary`. Exposed
    /// separately (not just folded into `reschedule`) so the in-app card can
    /// share this exact logic — currently the card builds its own summary
    /// off a `@Query` instead, since it needs live SwiftUI invalidation, but
    /// both paths run through `DigestBuilder` so they never disagree.
    static func buildSummary(modelContext: ModelContext) -> DigestSummary {
        let records: [PurchaseRecord]
        do {
            records = try modelContext.fetch(FetchDescriptor<PurchaseRecord>())
        } catch {
            AppLogger.error("Digest fetch failed: \(error.localizedDescription)", category: "digest")
            return DigestSummary()
        }
        return DigestBuilder.build(from: records.map(\.digestSnapshot))
    }

    /// The next 1st-of-the-month at 09:00 local — this month's if it hasn't
    /// passed yet, otherwise next month's.
    private static func nextFirstOfMonth9AM(now: Date = .now, calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month], from: now)
        components.day = 1
        components.hour = 9
        components.minute = 0
        components.second = 0
        guard let thisMonthFirst = calendar.date(from: components) else { return nil }
        if thisMonthFirst > now {
            return thisMonthFirst
        }
        return calendar.date(byAdding: .month, value: 1, to: thisMonthFirst)
    }
}

extension PurchaseRecord {
    /// Maps this record's live fields to the plain snapshot `DigestBuilder` consumes.
    var digestSnapshot: DigestRecordSnapshot {
        DigestRecordSnapshot(
            productName: productName,
            warrantyExpiryDate: warrantyExpiryDate,
            amount: amount,
            currency: currency,
            returnDeadline: returnDeadline,
            isRegistered: isRegistered
        )
    }
}
