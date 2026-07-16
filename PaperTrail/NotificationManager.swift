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

    /// Every warranty lead-time offset a reminder has *ever* been scheduled
    /// under, across every app version — used only to build the identifier
    /// superset `removeWarrantyReminders`/rescheduling clear before
    /// re-scheduling, so a stale reminder from an old lead-time setting or a
    /// pre-budget-fix build (which used to fire at 30/14/7/0 all at once,
    /// per DESIGN_LANGUAGE.md §8) never survives a reschedule. Scheduling
    /// itself only ever produces ONE of these — see `warrantyReminderPlan`.
    static let warrantyOffsets = [30, 14, 7, 0]

    /// Same idea as `warrantyOffsets`, for return-window reminders. Scheduling
    /// only ever produces the 3-days-before reminder (`returnWindowLeadDays`);
    /// `0` stays in this superset purely so a pre-budget-fix day-of reminder
    /// gets cleared on the next reschedule.
    static let returnWindowOffsets = [3, 0]

    /// The single lead time (days before the return deadline) a return-window
    /// reminder is scheduled at — DESIGN_LANGUAGE.md §8: "return-window (once)".
    static let returnWindowLeadDays = 3

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

    // MARK: - Reminder plans (pure, testable) — the notification budget

    /// A single reminder's identifier + fire date, or `nil` if nothing should
    /// fire (no date to anchor to, or the trigger would already be in the
    /// past). Pure so the "exactly one reminder per record" budget
    /// (DESIGN_LANGUAGE.md §8) is testable without `UNUserNotificationCenter`,
    /// which needs a device/simulator with notification entitlements CI
    /// doesn't have.
    struct ReminderPlan: Equatable {
        let identifier: String
        let triggerDate: Date
        let leadDays: Int
    }

    /// The one warranty reminder a record should have, at the user's chosen
    /// lead time. `nil` when there's no expiry date, it's already passed, or
    /// the lead time would fire in the past (e.g. the user set a 30-day lead
    /// but the warranty already expires in 10 days) — in that last case we
    /// don't fall back to a shorter lead; DESIGN_LANGUAGE.md §8 is "once", not
    /// "once, or best effort otherwise".
    static func warrantyReminderPlan(for record: PurchaseRecord, leadDays: Int, now: Date = .now) -> ReminderPlan? {
        guard let expiryDate = record.warrantyExpiryDate, expiryDate > now,
              let triggerDate = Calendar.current.date(byAdding: .day, value: -leadDays, to: expiryDate),
              triggerDate > now
        else { return nil }
        return ReminderPlan(
            identifier: warrantyIdentifier(recordID: record.id, offsetDays: leadDays),
            triggerDate: triggerDate,
            leadDays: leadDays
        )
    }

    /// The one return-window reminder a record should have, always at
    /// `returnWindowLeadDays` before the deadline.
    static func returnWindowReminderPlan(for record: PurchaseRecord, now: Date = .now) -> ReminderPlan? {
        guard let deadline = record.returnDeadline, deadline > now,
              let triggerDate = Calendar.current.date(byAdding: .day, value: -returnWindowLeadDays, to: deadline),
              triggerDate > now
        else { return nil }
        return ReminderPlan(
            identifier: returnWindowIdentifier(recordID: record.id, offsetDays: returnWindowLeadDays),
            triggerDate: triggerDate,
            leadDays: returnWindowLeadDays
        )
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

    /// Schedule the one warranty expiry reminder for a record, at `leadDays`
    /// before expiry (DESIGN_LANGUAGE.md §8 notification budget). Returns the
    /// number of requests submitted (0 or 1) — used both as a migration-sweep
    /// running total against the platform's pending-notification cap, and by
    /// callers to decide whether it's honest to mark the record as having a
    /// reminder scheduled.
    @discardableResult
    func scheduleWarrantyReminders(for record: PurchaseRecord, leadDays: Int = 14) -> Int {
        let center = UNUserNotificationCenter.current()

        // Clear every identifier this record could have under any
        // historical offset before (maybe) scheduling the one current one —
        // keeps a lead-time change or an old multi-reminder build from
        // leaving a stale extra reminder behind.
        center.removePendingNotificationRequests(withIdentifiers: Self.warrantyIdentifiers(recordID: record.id))

        guard let plan = Self.warrantyReminderPlan(for: record, leadDays: leadDays) else { return 0 }

        let content = UNMutableNotificationContent()
        content.title = "Warranty Expiring"
        content.body = "\(record.productName) warranty expires in \(plan.leadDays) day\(plan.leadDays == 1 ? "" : "s")."
        content.sound = .default
        content.categoryIdentifier = "WARRANTY_EXPIRY"
        content.userInfo = ["recordID": record.id.uuidString]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: plan.triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                AppLogger.error("Failed to schedule \(plan.identifier): \(error)", category: "notifications")
                // The request wasn't actually accepted (e.g. authorization
                // was revoked between the caller's settings check and this
                // callback) — don't leave the record's "scheduled" flag
                // lying about it; `rescheduleAll` is what re-arms it once
                // permission is genuinely granted.
                Task { @MainActor in
                    record.warrantyNotificationScheduled = false
                }
            }
        }
        return 1
    }

    /// Remove warranty notifications for a record.
    func removeWarrantyReminders(for record: PurchaseRecord) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.warrantyIdentifiers(recordID: record.id))
    }

    // MARK: - Return-window reminders (§6)

    /// Schedule the one return-window reminder for a record
    /// (`returnWindowLeadDays` before its `returnDeadline`). No-ops if the
    /// record has no window configured or purchase date to anchor it to.
    /// Returns the number of requests submitted (0 or 1) — see
    /// `scheduleWarrantyReminders` for why callers care about this value.
    @discardableResult
    func scheduleReturnWindowReminder(for record: PurchaseRecord) -> Int {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.returnWindowIdentifiers(recordID: record.id))

        guard let plan = Self.returnWindowReminderPlan(for: record) else { return 0 }

        let merchantSuffix = record.merchantName.map { " — \($0)" } ?? ""
        let content = UNMutableNotificationContent()
        content.title = "Return window closing"
        content.body = "Return window for \(record.productName) closes in \(plan.leadDays) day\(plan.leadDays == 1 ? "" : "s")\(merchantSuffix)."
        content.sound = .default
        content.categoryIdentifier = "RETURN_WINDOW"
        content.userInfo = ["recordID": record.id.uuidString]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: plan.triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                AppLogger.error("Failed to schedule \(plan.identifier): \(error)", category: "notifications")
                Task { @MainActor in
                    record.returnWindowNotificationScheduled = false
                }
            }
        }
        return 1
    }

    /// Remove all return-window reminders for a record.
    func removeReturnWindowReminder(for record: PurchaseRecord) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.returnWindowIdentifiers(recordID: record.id))
    }

    // MARK: - Reschedule-all (pure eligibility + the shared sweep)

    /// Which of `records` should get a reminder on a full reschedule, and in
    /// what order (soonest-first — see `rescheduleAll` for why order
    /// matters). Pure: the settings-respecting filter, pulled out of
    /// `rescheduleAll` so it's testable without `UNUserNotificationCenter`.
    static func eligibleForReschedule(
        records: [PurchaseRecord],
        warrantyRemindersEnabled: Bool,
        returnWindowRemindersEnabled: Bool
    ) -> [PurchaseRecord] {
        records.compactMap { record -> (record: PurchaseRecord, soonest: Date)? in
            var soonest: Date?
            if warrantyRemindersEnabled, let expiry = record.warrantyExpiryDate {
                soonest = expiry
            }
            if returnWindowRemindersEnabled, record.returnWindowDays != nil,
               let deadline = record.returnDeadline {
                soonest = min(soonest ?? deadline, deadline)
            }
            guard let soonest else { return nil }
            return (record, soonest)
        }
        .sorted { $0.soonest < $1.soonest }
        .map(\.record)
    }

    /// Re-schedules every eligible record's reminders from scratch,
    /// respecting `ReminderSettings` and the platform's pending-notification
    /// budget (50-request cap of our own, well under the OS's 64). Shared by
    /// the one-time identifier migration sweep (`migrateIdentifiersIfNeeded`)
    /// and `SoftAskCoordinator.respondYes()`: records saved *before* the user
    /// grants permission never get a real reminder scheduled (the
    /// authorization guard in `scheduleWarrantyReminders`/
    /// `scheduleReturnWindowReminder`'s completion handler only catches
    /// already-in-flight requests, not ones skipped because permission
    /// wasn't there yet at settings-check time) — nothing else re-arms them
    /// once permission actually lands.
    @MainActor
    @discardableResult
    func rescheduleAll(modelContext: ModelContext) async -> (warrantyRescheduled: Int, returnWindowRescheduled: Int) {
        let records: [PurchaseRecord]
        do {
            records = try modelContext.fetch(FetchDescriptor<PurchaseRecord>())
        } catch {
            AppLogger.error("rescheduleAll: record fetch failed: \(error)", category: "notifications")
            return (0, 0)
        }

        let reminderPrefs = ReminderSettings.shared
        let eligible = Self.eligibleForReschedule(
            records: records,
            warrantyRemindersEnabled: reminderPrefs.warrantyRemindersEnabled,
            returnWindowRemindersEnabled: reminderPrefs.returnWindowRemindersEnabled
        )

        let requestCap = 50
        var totalRequests = 0
        var warrantyRescheduled = 0
        var returnWindowRescheduled = 0
        var skippedRecords = 0

        for record in eligible {
            guard totalRequests < requestCap else {
                skippedRecords += 1
                continue
            }
            if reminderPrefs.warrantyRemindersEnabled, record.warrantyExpiryDate != nil {
                let count = scheduleWarrantyReminders(for: record, leadDays: reminderPrefs.warrantyLeadTime.days)
                record.warrantyNotificationScheduled = count > 0
                if count > 0 { warrantyRescheduled += 1 }
                totalRequests += count
            }
            if reminderPrefs.returnWindowRemindersEnabled, record.returnWindowDays != nil {
                let count = scheduleReturnWindowReminder(for: record)
                record.returnWindowNotificationScheduled = count > 0
                if count > 0 { returnWindowRescheduled += 1 }
                totalRequests += count
            }
        }

        if skippedRecords > 0 {
            AppLogger.warn(
                "rescheduleAll: skipped \(skippedRecords) record(s) after hitting the \(requestCap)-request cap",
                category: "notifications"
            )
        }
        return (warrantyRescheduled, returnWindowRescheduled)
    }

    // MARK: - Identifier migration (persistentModelID → UUID)

    /// One-time sweep, run at app launch: clears every pending reminder scheduled
    /// under the old `persistentModelID`-keyed identifiers (which
    /// `removeWarrantyReminders`/`removeReturnWindowReminder` could never reliably
    /// cancel — see the type doc above) and reschedules current reminders for
    /// every record via `rescheduleAll`. No-ops after the first successful run
    /// (`migrationFlagKey`).
    ///
    /// The SwiftData count check happens FIRST: if it throws, the sweep logs
    /// and returns without touching any pending notification or setting the
    /// migration flag, so the next launch retries from scratch rather than
    /// leaving every reminder in the app permanently wiped.
    @MainActor
    func migrateIdentifiersIfNeeded(modelContext: ModelContext) async {
        guard !UserDefaults.standard.bool(forKey: Self.migrationFlagKey) else { return }

        let recordCount: Int
        do {
            recordCount = try modelContext.fetchCount(FetchDescriptor<PurchaseRecord>())
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

        let (warrantyRescheduled, returnWindowRescheduled) = await rescheduleAll(modelContext: modelContext)

        UserDefaults.standard.set(true, forKey: Self.migrationFlagKey)
        AppLogger.info(
            "Notification ID migration: cleared \(staleIdentifiers.count) stale reminder(s); "
                + "rescheduled \(warrantyRescheduled) warranty + \(returnWindowRescheduled) return-window "
                + "reminder(s) across \(recordCount) record(s)",
            category: "notifications"
        )
    }
}
