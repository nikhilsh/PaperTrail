import Foundation
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
    /// Schedules at 30 days before, 7 days before, and on expiry day.
    func scheduleWarrantyReminders(for record: PurchaseRecord) {
        guard let expiryDate = record.warrantyExpiryDate, expiryDate > .now else { return }

        let recordID = record.persistentModelID.hashValue
        let center = UNUserNotificationCenter.current()

        // Remove any existing notifications for this record
        let identifiers = reminderIdentifiers(for: recordID)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let intervals: [(days: Int, label: String)] = [
            (30, "30 days"),
            (7, "7 days"),
            (0, "today"),
        ]

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
        let recordID = record.persistentModelID.hashValue
        let identifiers = reminderIdentifiers(for: recordID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func reminderIdentifiers(for recordHash: Int) -> [String] {
        [30, 7, 0].map { "\(recordHash)-warranty-\($0)" }
    }
}
