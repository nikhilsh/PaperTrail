import Foundation
import SwiftData
import WidgetKit

/// One upcoming event surfaced on the widget — a warranty expiry or a return
/// deadline. Plain `Codable` value type on purpose: this is the App Group
/// JSON contract between the app and the `PaperTrailWidgets` extension, which
/// has no access to SwiftData (CLAUDE.md: the widget must never touch the
/// CloudKit-backed store). The widget target keeps its own copy of this
/// shape — there's no shared framework between the two targets — so any
/// change here must be mirrored in `PaperTrailWidgets/WidgetSnapshot.swift`.
struct WidgetSnapshotItem: Codable, Sendable, Identifiable {
    /// The `PurchaseRecord` this event belongs to — what the widget's deep
    /// links resolve to (`papertrail://record/<recordID>`).
    var recordID: UUID
    var name: String
    /// "warranty" or "return"
    var kind: String
    var date: Date

    /// A single record can produce both a "warranty" and a "return" event
    /// (see `widgetCandidates`) — `recordID` alone collided as `Identifiable`
    /// `id` and caused SwiftUI `ForEach`/List identity clashes in the widget
    /// (e.g. `MediumWidgetView`'s row list). Computed, not stored, so it's
    /// never out of sync with `recordID`/`kind` and doesn't duplicate them
    /// in the JSON.
    var id: String { "\(recordID)-\(kind)" }
}

/// The first unregistered item that still has an active warranty — surfaced
/// as a gold "register it" nudge on the v3 `shelfWidgets` "Closing soon"
/// widget. `nil` when nothing qualifies.
struct WidgetRegisterNudge: Codable, Sendable, Equatable {
    var recordID: UUID
    var name: String
}

/// The full snapshot written to the App Group container.
///
/// `coveredCount`/`totalCount`/`totalValueText`/`registerNudge` are v3
/// `shelfWidgets` additions (`docs/design-v3/V3_BRIEF.md` §1) — all
/// `Optional`, so a pre-v3 JSON blob on disk (missing these keys) still
/// decodes cleanly with them as `nil`: Swift's synthesized `Decodable`
/// already treats a missing key as `nil` for `Optional` stored properties,
/// no custom `init(from:)` needed. Encoding mirrors that: a `nil` value is
/// omitted from the JSON entirely rather than written as `null`.
struct WidgetSnapshot: Codable, Sendable {
    var generatedAt: Date
    var items: [WidgetSnapshotItem]
    var coveredCount: Int? = nil
    var totalCount: Int? = nil
    /// Preformatted total value across all records, in the dominant
    /// currency (the currency with the largest summed `amount`), e.g.
    /// `"SGD 3,116"`. `nil` when no record has both an amount and currency.
    var totalValueText: String? = nil
    var registerNudge: WidgetRegisterNudge? = nil
}

/// Writes `widget-snapshot.json` to the shared App Group container and
/// nudges WidgetKit to reload. Called from the same app-foreground hook as
/// `DigestScheduler.reschedule` so the widget is never more stale than the
/// digest.
@MainActor
enum WidgetSnapshotWriter {
    static let appGroupIdentifier = "group.nikhilsh.PaperTrail"
    private static let snapshotFileName = "widget-snapshot.json"
    private static let maxItems = 6

    /// Call from app-foreground, alongside `DigestScheduler.reschedule` in
    /// `AppShellView`. Fetches its own records — kept for tests and any
    /// other direct caller. The foreground hook itself goes through
    /// `ForegroundRefreshCoordinator`, which fetches once and feeds both
    /// this and `DigestScheduler` from the same records via
    /// `write(records:)`.
    static func write(modelContext: ModelContext) {
        let records: [PurchaseRecord]
        do {
            records = try modelContext.fetch(FetchDescriptor<PurchaseRecord>())
        } catch {
            AppLogger.error("Widget snapshot fetch failed: \(error.localizedDescription)", category: "widget")
            return
        }
        write(records: records)
    }

    /// Same as `write(modelContext:)` but over already-fetched records, so
    /// a caller that also needs those records elsewhere (e.g.
    /// `ForegroundRefreshCoordinator`, which feeds `DigestScheduler` from
    /// the same fetch) doesn't pay for a second SwiftData fetch.
    static func write(records: [PurchaseRecord]) {
        let candidates = records.flatMap(\.widgetCandidates)
        let items = nearestUpcoming(from: candidates, limit: maxItems)
        let coverage = coverageCounts(for: records)
        let snapshot = WidgetSnapshot(
            generatedAt: .now,
            items: items,
            coveredCount: coverage.covered,
            totalCount: coverage.total,
            totalValueText: dominantCurrencyTotalText(for: records),
            registerNudge: registerNudgeCandidate(for: records)
        )

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            AppLogger.error("Widget snapshot: App Group container unavailable", category: "widget")
            return
        }

        let fileURL = containerURL.appendingPathComponent(snapshotFileName)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            excludeFromBackup(fileURL)
        } catch {
            AppLogger.error("Widget snapshot write failed: \(error.localizedDescription)", category: "widget")
            return
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The snapshot is small, regenerated every foreground, and purely
    /// App Group-local — it doesn't belong in an iCloud/iTunes device
    /// backup. Best-effort: failures are silently ignored, this is hygiene,
    /// not correctness.
    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Nearest `limit` upcoming events across mixed warranty/return
    /// candidates, excluding anything already past (day granularity, so
    /// "today" still counts), sorted ascending by date. Pure function over
    /// plain value types — no SwiftData, no App Group I/O — so it's directly
    /// unit-testable. `nonisolated` (unlike the rest of this `@MainActor`
    /// enum) so tests can call it directly without hopping actors.
    nonisolated static func nearestUpcoming(
        from candidates: [WidgetSnapshotItem],
        limit: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [WidgetSnapshotItem] {
        let today = calendar.startOfDay(for: now)
        return candidates
            .filter { calendar.startOfDay(for: $0.date) >= today }
            .sorted { $0.date < $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// `(covered, total)` for the shelfWidgets coverage ring: `total` is
    /// every record; `covered` is the subset with a warranty that hasn't
    /// expired yet (day granularity, so "expires today" still counts —
    /// matching `PurchaseRecord.warrantyStatus`/`DigestBuilder`). Pure,
    /// `nonisolated`, directly testable.
    nonisolated static func coverageCounts(
        for records: [PurchaseRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (covered: Int, total: Int) {
        let today = calendar.startOfDay(for: now)
        let covered = records.filter { record in
            guard let expiry = record.warrantyExpiryDate else { return false }
            return calendar.startOfDay(for: expiry) >= today
        }.count
        return (covered, records.count)
    }

    /// Total `amount` across all records, summed within and formatted for
    /// the currency that holds the largest total (ties broken alphabetically
    /// by currency code, for determinism) — e.g. `"SGD 3,116"`. Records with
    /// no `amount` are skipped; a `nil` `currency` defaults to `"SGD"`,
    /// matching `DigestBuilder.totals`/`PurchaseRecord.formattedAmount`.
    /// `nil` when no record has an amount. Code + amount (not a locale
    /// currency symbol) so the string is deterministic across devices —
    /// same rationale as `DigestSummary.totalsText`.
    nonisolated static func dominantCurrencyTotalText(for records: [PurchaseRecord]) -> String? {
        var totalsByCurrency: [String: Double] = [:]
        for record in records {
            guard let amount = record.amount else { continue }
            let currency = record.currency ?? "SGD"
            totalsByCurrency[currency, default: 0] += amount
        }
        // Highest total wins; a tie goes to the alphabetically-first
        // currency code. The comparator folds the tie-break in directly
        // (an alphabetically-later key compares "less" on equal totals),
        // so the maximum is unique — no reliance on `max(by:)`'s
        // first-vs-last behavior for equal elements or on dictionary
        // iteration order.
        guard let dominant = totalsByCurrency.max(by: { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }) else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // en_US_POSIX doesn't group digits on its own — force the comma so
        // the widget shows "SGD 3,116" (the C1 mock's copy), still
        // deterministic across device locales because both the locale and
        // the separator are pinned here.
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        let amountText = formatter.string(from: NSNumber(value: dominant.value)) ?? "\(Int(dominant.value))"
        return "\(dominant.key) \(amountText)"
    }

    /// The first unregistered item whose warranty is still active — the
    /// "Closing soon" widget's gold nudge row. Deterministic ordering:
    /// soonest-expiring first, then product name — mirrors
    /// `DigestBuilder.build`'s sort for the same underlying condition
    /// (`!isRegistered && warranty not yet expired`). `nil` when nothing
    /// qualifies.
    nonisolated static func registerNudgeCandidate(
        for records: [PurchaseRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WidgetRegisterNudge? {
        let today = calendar.startOfDay(for: now)
        let candidates: [(record: PurchaseRecord, daysLeft: Int)] = records.compactMap { record in
            guard !record.isRegistered, let expiry = record.warrantyExpiryDate else { return nil }
            let expiryDay = calendar.startOfDay(for: expiry)
            guard expiryDay >= today else { return nil }
            let daysLeft = calendar.dateComponents([.day], from: today, to: expiryDay).day ?? 0
            return (record, daysLeft)
        }
        let sorted = candidates.sorted {
            $0.daysLeft != $1.daysLeft ? $0.daysLeft < $1.daysLeft : $0.record.productName < $1.record.productName
        }
        guard let first = sorted.first else { return nil }
        return WidgetRegisterNudge(recordID: first.record.id, name: first.record.productName)
    }
}

extension PurchaseRecord {
    /// This record's candidate widget events — a warranty-expiry entry
    /// and/or a return-deadline entry, whichever are tracked. Not yet
    /// filtered for past dates or trimmed to a limit; that's
    /// `WidgetSnapshotWriter.nearestUpcoming`'s job. Mirrors the shape of
    /// `digestSnapshot` in `DigestScheduler.swift`.
    nonisolated var widgetCandidates: [WidgetSnapshotItem] {
        var items: [WidgetSnapshotItem] = []
        if let warrantyExpiryDate {
            items.append(WidgetSnapshotItem(recordID: id, name: productName, kind: "warranty", date: warrantyExpiryDate))
        }
        if let returnDeadline {
            items.append(WidgetSnapshotItem(recordID: id, name: productName, kind: "return", date: returnDeadline))
        }
        return items
    }
}
