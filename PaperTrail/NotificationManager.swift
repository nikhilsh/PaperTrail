import Foundation
import SwiftData
import UserNotifications

/// Manages local notifications for warranty expiry and return-window reminders.
///
/// Identifiers are keyed on `record.id` (the model's stable `UUID`), never on
/// `PersistentIdentifier`. A just-inserted SwiftData object is assigned a
/// *temporary* `persistentModelID` that changes once CloudKit assigns the
/// permanent one — identifiers built from it at schedule time silently stop
/// matching the identifiers `removeWarrantyReminders`/`removeReturnWindowReminder`
/// compute later, leaking notifications for deleted/edited records that then
/// tap through to "Record not found". `record.id` is stable from creation, so
/// it doesn't have this problem.
struct NotificationManager {
    static let shared = NotificationManager()

    /// UserDefaults flag guarding the one-time sweep (`migrateIdentifiersIfNeeded`)
    /// that clears reminders scheduled under the old `persistentModelID`-keyed
    /// identifiers and reschedules current ones under the new UUID-keyed scheme.
    static let migrationFlagKey = "notificationIDMigration.v1"

    /// `categoryIdentifier`s used by every per-record reminder this manager
    /// schedules. The migration sweep uses this to recognize old- and new-format
    /// reminders alike without touching unrelated notification categories (e.g.
    /// a future digest feature).
    static let reminderCategories: Set<String> = ["WARRANTY_EXPIRY", "RETURN_WINDOW"]

    // MARK: - Identifier formats (pure, testable)

    static let warrantyOffsets = [30, 14, 7, 0]
    static let returnWindowOffsets = [3, 0]

    /// Warranty reminder identifier. Format: "warranty-<uuid>-<days>d" (day-of
    /// reminder uses "0d").
    static func warrantyIdentifier(recordID: UUID, offsetDays: Int) -> String {
        "warranty-\(recordID.uuidString)-\(offsetDays)d"
    }

    /// Every warranty identifier that could exist for a record, covering every
    /// lead-time offset so re-scheduling never leaves a stale reminder behind.
    static func warrantyIdentifiers(recordID: UUID) -> [String] {
        warrantyOffsets.map { warrantyIdentifier(recordID: recordID, offsetDays: $0) }
    }

    /// Return-window reminder identifier. Format: "return-window-<uuid>-<days>d".
    static func returnWindowIdentifier(recordID: UUID, offsetDays: Int) -> String {
        "return-window-\(recordID.uuidString)-\(offsetDays)d"
    }

    static func returnWindowIdentifiers(recordID: UUID) -> [String] {
        returnWindowOffsets.map { returnWindowIdentifier(recordID: recordID, offsetDays: $0) }
    }

    /// Extracts the record UUID from a *current-format* identifier ("warranty-
    /// <uuid>-Nd" / "return-window-<uuid>-Nd"). Returns `nil` for anything else —
    /// including every identifier the old `persistentModelID`-keyed scheme ever
    /// produced, since those never started with a bare "warranty-"/"return-window-"
    /// prefix followed by a valid UUID. That's what makes old vs. new
    /// distinguishable during migration without tracking every historical format.
    static func recordID(fromCurrentFormatIdentifier identifier: String) -> UUID? {
        for prefix in ["warranty-", "return-window-"] {
            guard identifier.hasPrefix(prefix) else { continue }
            let remainder = identifier.dropFirst(prefix.count)
            // The offset suffix ("Nd") never itself contains a dash, so the last
            // dash in the remainder is always the one separating the UUID
            // (which does contain dashes) from the suffix.
            guard let lastDash = remainder.range(of: "-", options: .backwards) else { return nil }
            return UUID(uuidString: String(remainder[remainder.startIndex..<lastDash.lowerBound]))
        }
        return nil
    }

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
    /// Returns the number of requests submitted (used by the migration sweep to
    /// track the total against the platform's pending-notification cap).
    @discardableResult
    func scheduleWarrantyReminders(for record: PurchaseRecord, leadDays: Int = 14) -> Int {
        guard let expiryDate = record.warrantyExpiryDate, expiryDate > .now else { return 0 }

        let center = UNUserNotificationCenter.current()

        // Remove any existing notifications for this record
        center.removePendingNotificationRequests(withIdentifiers: Self.warrantyIdentifiers(recordID: record.id))

        // The configured lead time drives the first reminder; 7-day and day-of
        // follow-ups are always useful. Deduped + sorted soonest-first.
        let offsets = Array(Set([leadDays, 7, 0])).sorted(by: >)
        let intervals: [(days: Int, label: String)] = offsets.map { days in
            (days, days == 0 ? "today" : "\(days) days")
        }

        var scheduledCount = 0
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

            let id = Self.warrantyIdentifier(recordID: record.id, offsetDays: interval.days)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            center.add(request) { error in
                if let error {
                    AppLogger.error("Failed to schedule \(id): \(error)", category: "notifications")
                }
            }
            scheduledCount += 1
        }
        return scheduledCount
    }

    /// Remove warranty notifications for a record.
    func removeWarrantyReminders(for record: PurchaseRecord) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.warrantyIdentifiers(recordID: record.id))
    }

    // MARK: - Return-window reminders (§6)

    /// Schedule return-window reminders for a record, using its own
    /// `returnWindowDays` (set via the return-window picker). No-ops if the
    /// record has no window configured or purchase date to anchor it to.
    /// Returns the number of requests submitted (used by the migration sweep to
    /// track the total against the platform's pending-notification cap).
    @discardableResult
    func scheduleReturnWindowReminder(for record: PurchaseRecord) -> Int {
        guard let deadline = record.returnDeadline, deadline > .now else { return 0 }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.returnWindowIdentifiers(recordID: record.id))

        let merchantSuffix = record.merchantName.map { " — \($0)" } ?? ""

        var scheduledCount = 0
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

            let id = Self.returnWindowIdentifier(recordID: record.id, offsetDays: days)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(request) { error in
                if let error {
                    AppLogger.error("Failed to schedule \(id): \(error)", category: "notifications")
                }
            }
            scheduledCount += 1
        }
        return scheduledCount
    }

    /// Remove all return-window reminders for a record.
    func removeReturnWindowReminder(for record: PurchaseRecord) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.returnWindowIdentifiers(recordID: record.id))
    }

    // MARK: - Identifier migration (persistentModelID → UUID)

    /// One-time sweep, run at app launch: clears every pending reminder scheduled
    /// under the old `persistentModelID`-keyed identifiers (which
    /// `removeWarrantyReminders`/`removeReturnWindowReminder` could never reliably
    /// cancel — see the type doc above) and reschedules current reminders for
    /// every record through the normal, already-idempotent scheduling entry
    /// points. No-ops after the first successful run (`migrationFlagKey`).
    ///
    /// The SwiftData fetch happens FIRST: if it throws, the sweep logs and
    /// returns without touching any pending notification or setting the
    /// migration flag, so the next launch retries from scratch rather than
    /// leaving every reminder in the app permanently wiped.
    @MainActor
    func migrateIdentifiersIfNeeded(modelContext: ModelContext) async {
        guard !UserDefaults.standard.bool(forKey: Self.migrationFlagKey) else { return }

        let records: [PurchaseRecord]
        do {
            records = try modelContext.fetch(FetchDescriptor<PurchaseRecord>())
        } catch {
            AppLogger.error(
                "Notification ID migration: record fetch failed, aborting sweep without removing "
                    + "anything: \(error)",
                category: "notifications"
            )
            return
        }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()

        let staleIdentifiers = pending
            .filter { Self.reminderCategories.contains($0.content.categoryIdentifier) }
            .map(\.identifier)
            .filter { Self.recordID(fromCurrentFormatIdentifier: $0) == nil }

        if !staleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
        }

        let reminderPrefs = ReminderSettings.shared

        // Records that would actually get a reminder scheduled, sorted by the
        // soonest date driving that reminder — the platform caps pending
        // notifications at 64, so when there are more eligible records than
        // fit under our own 50-request budget, the soonest-firing reminders
        // win.
        let eligible = records.compactMap { record -> (record: PurchaseRecord, soonest: Date)? in
            var soonest: Date?
            if reminderPrefs.warrantyRemindersEnabled, let expiry = record.warrantyExpiryDate {
                soonest = expiry
            }
            if reminderPrefs.returnWindowRemindersEnabled, record.returnWindowDays != nil,
               let deadline = record.returnDeadline {
                soonest = min(soonest ?? deadline, deadline)
            }
            guard let soonest else { return nil }
            return (record, soonest)
        }.sorted { $0.soonest < $1.soonest }

        let requestCap = 50
        var totalRequests = 0
        var warrantyRescheduled = 0
        var returnWindowRescheduled = 0
        var skippedRecords = 0

        for entry in eligible {
            guard totalRequests < requestCap else {
                skippedRecords += 1
                continue
            }
            let record = entry.record
            if reminderPrefs.warrantyRemindersEnabled, record.warrantyExpiryDate != nil {
                let count = scheduleWarrantyReminders(for: record, leadDays: reminderPrefs.warrantyLeadTime.days)
                if count > 0 { warrantyRescheduled += 1 }
                totalRequests += count
            }
            if reminderPrefs.returnWindowRemindersEnabled, record.returnWindowDays != nil {
                let count = scheduleReturnWindowReminder(for: record)
                if count > 0 { returnWindowRescheduled += 1 }
                totalRequests += count
            }
        }

        if skippedRecords > 0 {
            AppLogger.warn(
                "Notification ID migration: skipped \(skippedRecords) record(s) after hitting the "
                    + "\(requestCap)-request cap",
                category: "notifications"
            )
        }

        UserDefaults.standard.set(true, forKey: Self.migrationFlagKey)
        AppLogger.info(
            "Notification ID migration: cleared \(staleIdentifiers.count) stale reminder(s); "
                + "rescheduled \(warrantyRescheduled) warranty + \(returnWindowRescheduled) return-window "
                + "reminder(s) across \(records.count) record(s)",
            category: "notifications"
        )
    }
}
