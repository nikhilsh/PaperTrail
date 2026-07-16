import Foundation
import UserNotifications

// MARK: - CoverageReminders (docs/design-v3/V3_BRIEF.md §2-3, `multiCoverage`)
//
// Per-line warranty-style reminders for coverage lines that carry an
// `endDate`. Mirrors `NotificationManager`'s identifier/schedule shape
// (record-UUID-keyed identifiers, remove-then-reschedule on save) but lives
// in its own type — this wave owns coverage-line reminders independently of
// `NotificationManager` (see the task's file-ownership boundaries). Every
// entry point no-ops when `FeatureFlags.isOn(.multiCoverage)` is false, so a
// flag-off client neither schedules nor removes anything through this type.

enum CoverageReminders {
    /// `categoryIdentifier` for every notification this type schedules —
    /// deliberately outside `NotificationManager.reminderCategories`, so the
    /// existing identifier-migration sweep (which only recognizes
    /// "WARRANTY_EXPIRY" / "RETURN_WINDOW") never touches these.
    static let category = "COVERAGE_LINE"

    /// Identifier format: "coverage-<recordUUID>-<lineIndex>-<days>d".
    nonisolated static func identifier(recordID: UUID, lineIndex: Int, offsetDays: Int) -> String {
        "coverage-\(recordID.uuidString)-\(lineIndex)-\(offsetDays)d"
    }

    /// Lead-time offset applied to every dated coverage line — lead-time
    /// only, no separate day-of (0) nudge: a coverage line already gets a
    /// day-of feel from whichever cluster it's grouped into (§3 dedupe), and
    /// a second same-day notification per line was pure noise against the
    /// ~2/month cap discipline every other reminder in this app respects.
    nonisolated static func offsets(leadDays: Int) -> [Int] {
        [max(0, leadDays)]
    }

    // MARK: - Deadline-proximity grouping (§3 dedupe)

    /// One dated coverage line, reduced to just what grouping/scheduling need.
    nonisolated struct DatedLine: Equatable {
        let index: Int
        let label: String
        let endDate: Date
    }

    /// Groups dated lines into clusters whose neighbors (sorted by `endDate`)
    /// are ≤7 days apart, so each cluster collapses into ONE notification
    /// listing every label in it (V3_BRIEF §2: "deduped into one notification
    /// when ≤7 days apart"). Chain-grouping: A and C land in the same group
    /// if A–B and B–C are each ≤7 days apart, even when A–C alone exceeds 7.
    nonisolated static func groupByDeadlineProximity(_ lines: [DatedLine]) -> [[DatedLine]] {
        let sorted = lines.sorted { $0.endDate < $1.endDate }
        var groups: [[DatedLine]] = []
        for line in sorted {
            if let lastEnd = groups.last?.last?.endDate,
               let days = Calendar.current.dateComponents([.day], from: lastEnd, to: line.endDate).day,
               days <= 7 {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups
    }

    /// True when `endDate` falls within 7 days of the record's own
    /// `warrantyExpiryDate` — such a line's own reminder would duplicate the
    /// existing single warranty reminder (`NotificationManager`'s), so
    /// `reschedule` skips scheduling one for it. Same 7-day window as the
    /// line-to-line dedupe above, extended to the record's legacy warranty
    /// date. `nil` warrantyExpiryDate never dedupes anything.
    nonisolated static func isDuplicateOfWarranty(endDate: Date, warrantyExpiryDate: Date?, calendar: Calendar = .current) -> Bool {
        guard let warrantyExpiryDate else { return false }
        guard let days = calendar.dateComponents([.day], from: warrantyExpiryDate, to: endDate).day else { return false }
        return abs(days) <= 7
    }

    /// Notification body listing every label in a deduped group.
    nonisolated static func body(productName: String, labels: [String], daysLeft: Int) -> String {
        let joined = labels.joined(separator: " & ")
        if daysLeft > 0 {
            return "\(productName) — \(joined) expires in \(daysLeft) day\(daysLeft == 1 ? "" : "s")."
        }
        return "\(productName) — \(joined) expires today."
    }

    // MARK: - Schedule / remove (impure — UNUserNotificationCenter)

    /// Removes every pending coverage reminder for `recordID`, regardless of
    /// how many lines it currently has, so lines deleted or re-ordered since
    /// the last schedule never leak stale requests. Unlike
    /// `NotificationManager`'s fixed-offset removal (safe because warranty/
    /// return-window always compute the same identifier set from the current
    /// record alone), coverage-line identifiers are keyed on a per-record
    /// array index that shrinks when a line is deleted — enumerating pending
    /// requests and matching by prefix is what actually clears those.
    static func removeReminders(for recordID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "coverage-\(recordID.uuidString)-"
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        guard !stale.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    /// Clears then reschedules every per-line reminder for `record`'s current
    /// `coverageLines`, deduping clusters ≤7 days apart into one notification
    /// (§3). No-ops entirely — doesn't even clear stale requests — when the
    /// flag is off, per V3_BRIEF §2's "all of it no-ops when the flag is
    /// off." Call on record save, mirroring where
    /// `NotificationManager.scheduleWarrantyReminders` is hooked in
    /// `EditRecordView.saveEdits()`.
    @discardableResult
    static func reschedule(for record: PurchaseRecord, leadDays: Int) async -> Int {
        guard FeatureFlags.isOn(.multiCoverage) else { return 0 }

        let recordID = record.id
        let productName = record.productName
        let lines = record.coverageLines

        await removeReminders(for: recordID)

        let dated = lines.enumerated().compactMap { index, line -> DatedLine? in
            guard let endDate = line.endDate, endDate > .now else { return nil }
            // Skip a line that's within 7 days of the record's own
            // warranty expiry — its reminder would just duplicate the
            // existing warranty single (dedupe vs. warranty, §6).
            guard !isDuplicateOfWarranty(endDate: endDate, warrantyExpiryDate: record.warrantyExpiryDate) else { return nil }
            return DatedLine(index: index, label: line.label, endDate: endDate)
        }
        guard !dated.isEmpty else { return 0 }

        let center = UNUserNotificationCenter.current()
        var scheduledCount = 0

        for group in groupByDeadlineProximity(dated) {
            guard let representative = group.first else { continue }
            let labels = group.map(\.label)

            for days in offsets(leadDays: leadDays) {
                guard let triggerDate = Calendar.current.date(byAdding: .day, value: -days, to: representative.endDate),
                      triggerDate > .now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Coverage ending"
                content.body = Self.body(productName: productName, labels: labels, daysLeft: days)
                content.sound = .default
                content.categoryIdentifier = category
                content.userInfo = ["recordID": recordID.uuidString]

                let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: triggerDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

                let id = identifier(recordID: recordID, lineIndex: representative.index, offsetDays: days)
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                center.add(request) { error in
                    if let error {
                        AppLogger.error("CoverageReminders: failed to schedule \(id): \(error)", category: "notifications")
                    }
                }
                scheduledCount += 1
            }
        }
        return scheduledCount
    }
}
