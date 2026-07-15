import Foundation
import SwiftData
import UserNotifications

/// Manages local notifications for warranty expiry reminders.
struct NotificationManager {
    static let shared = NotificationManager()

    /// Request notification permission.
    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("NotificationManager: permission request failed: \(error)")
            return false
        }
    }

    /// Schedule warranty expiry reminders for a record.
    /// Schedules at the user's chosen lead time, 7 days before, and on expiry day.
    func scheduleWarrantyReminders(for record: PurchaseRecord, leadDays: Int = 14) {
        guard let expiryDate = record.warrantyExpiryDate, expiryDate > .now else { return }

        let recordID = String(describing: record.persistentModelID)
        let center = UNUserNotificationCenter.current()

        // Remove any existing notifications for this record
        let identifiers = reminderIdentifiers(for: recordID)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        // The configured lead time drives the first reminder; 7-day and day-of
        // follow-ups are always useful. Deduped + sorted soonest-first.
        let offsets = Array(Set([leadDays, 7, 0])).sorted(by: >)
        let intervals: [(days: Int, label: String)] = offsets.map { days in
            (days, days == 0 ? "today" : "\(days) days")
        }

        for interval in intervals {
            guard let triggerDate = Calendar.current.date(byAdding: .day, value: -interval.days, to: expiryDate),
                  triggerDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Warranty Expiring"
            if interval.days > 0 {
                content.body = "\(record.productName) warranty expires in \(interval.label)."
            } else {
                content.body = "\(record.productName) warranty expires \(interval.label)!"
            }
            content.sound = .default
            content.categoryIdentifier = "WARRANTY_EXPIRY"
            content.userInfo = ["recordID": record.id.uuidString]

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let id = "\(recordID)-warranty-\(interval.days)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            center.add(request) { error in
                if let error {
                    print("NotificationManager: failed to schedule \(id): \(error)")
                }
            }
        }
    }

    /// Remove warranty notifications for a record.
    func removeWarrantyReminders(for record: PurchaseRecord) {
        let recordID = String(describing: record.persistentModelID)
        let identifiers = reminderIdentifiers(for: recordID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func reminderIdentifiers(for recordHash: String) -> [String] {
        // Covers every possible lead-time offset so re-scheduling never leaves
        // a stale reminder behind.
        [30, 14, 7, 0].map { "\(recordHash)-warranty-\($0)" }
    }

    // MARK: - Return-window reminders (§6)

    /// Reminders fire this many days before `record.returnDeadline`, plus a
    /// day-of reminder (`0`). Mirrors `scheduleWarrantyReminders`'s offset pattern.
    private static let returnWindowOffsets = [3, 0]

    /// Schedule return-window reminders for a record, using its own
    /// `returnWindowDays` (set via the return-window picker). No-ops if the
    /// record has no window configured or purchase date to anchor it to.
    func scheduleReturnWindowReminder(for record: PurchaseRecord) {
        guard let deadline = record.returnDeadline, deadline > .now else { return }

        let identifiers = returnWindowIdentifiers(for: record)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let merchantSuffix = record.merchantName.map { " — \($0)" } ?? ""

        for days in Self.returnWindowOffsets {
            guard let triggerDate = Calendar.current.date(byAdding: .day, value: -days, to: deadline),
                  triggerDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Return window closing"
            if days > 0 {
                content.body = "Return window for \(record.productName) closes in \(days) day\(days == 1 ? "" : "s")\(merchantSuffix)."
            } else {
                content.body = "Return window for \(record.productName) closes today\(merchantSuffix)."
            }
            content.sound = .default
            content.categoryIdentifier = "RETURN_WINDOW"
            content.userInfo = ["recordID": record.id.uuidString]

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let id = "\(recordIdentifier(record))-return-window-\(days)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(request) { error in
                if let error { print("NotificationManager: failed to schedule \(id): \(error)") }
            }
        }
    }

    /// Remove all return-window reminders for a record.
    func removeReturnWindowReminder(for record: PurchaseRecord) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: returnWindowIdentifiers(for: record))
    }

    private func returnWindowIdentifiers(for record: PurchaseRecord) -> [String] {
        let base = recordIdentifier(record)
        // Includes the legacy single-reminder id ("-return-window", no offset
        // suffix) so upgrading users don't keep a stale reminder scheduled
        // under the old identifier scheme.
        return Self.returnWindowOffsets.map { "\(base)-return-window-\($0)" } + ["\(base)-return-window"]
    }

    private func recordIdentifier(_ record: PurchaseRecord) -> String {
        String(describing: record.persistentModelID)
    }
}
