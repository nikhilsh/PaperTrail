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

    /// Schedule a single reminder a few days before a recent purchase's return /
    /// refund window closes. The habit-forming hook: weekly value, not
    /// once-a-year-warranty value.
    func scheduleReturnWindowReminder(for record: PurchaseRecord, windowDays: Int = 30, leadDays: Int = 3) {
        guard let purchaseDate = record.purchaseDate else { return }
        let closeDate = Calendar.current.date(byAdding: .day, value: windowDays, to: purchaseDate) ?? purchaseDate
        guard let triggerDate = Calendar.current.date(byAdding: .day, value: -leadDays, to: closeDate),
              triggerDate > .now else { return }

        let id = returnWindowIdentifier(for: record)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Return window closing"
        content.body = "\(record.productName): the return or refund window may be closing soon."
        content.sound = .default
        content.categoryIdentifier = "RETURN_WINDOW"

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { print("NotificationManager: failed to schedule return-window reminder: \(error)") }
        }
    }

    /// Remove the return-window reminder for a record.
    func removeReturnWindowReminder(for record: PurchaseRecord) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [returnWindowIdentifier(for: record)])
    }

    private func returnWindowIdentifier(for record: PurchaseRecord) -> String {
        "\(String(describing: record.persistentModelID))-return-window"
    }
}
