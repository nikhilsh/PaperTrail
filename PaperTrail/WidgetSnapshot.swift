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

/// The first unregistered, recently purchased (≤ 30 days) item that still
/// has an active warranty — surfaced as a gold "register it" nudge on the
/// v3 `shelfWidgets` "Closing soon" widget. `nil` when nothing qualifies.
/// `name` is the display form (`displayProductName`), never raw OCR.
struct WidgetRegisterNudge: Codable, Sendable, Equatable {
    var recordID: UUID
    var name: String
}

/// The full snapshot written to the App Group container.
///
/// `coveredCount`/`totalCount`/`totalValueText`/`totalValueCompactText`/
/// `registerNudge` are v3 `shelfWidgets` additions (`docs/design-v3/V3_BRIEF.md`
/// §1) — all `Optional`, so a pre-v3 JSON blob on disk (missing these keys)
/// still decodes cleanly with them as `nil`: Swift's synthesized `Decodable`
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
    /// Abbreviated form of `totalValueText`, e.g. `"S$3.1k"` — added later
    /// than the other v3 fields so the same additive-optional rule applies:
    /// a snapshot written by an app build that predates this field simply
    /// omits the key, and the widget falls back to `totalValueText`.
    var totalValueCompactText: String? = nil
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
        // v3 passItOn (docs/design-v3/V3_BRIEF.md §7, flagged): a passed-on
        // item shouldn't show up on the widget's "closing soon" list or
        // count toward its coverage ring/total-value text — it's not owned
        // anymore. Collapses back to `records` exactly when the flag is off.
        let records = records.filter {
            !PassItOnAggregation.isExcludedFromAggregates(passedOnDate: $0.passedOnDate, flagOn: FeatureFlags.isOn(.passItOn))
        }
        let candidates = records.flatMap(\.widgetCandidates)
        let items = nearestUpcoming(from: candidates, limit: maxItems)
        let coverage = coverageCounts(for: records)
        let snapshot = WidgetSnapshot(
            generatedAt: .now,
            items: items,
            coveredCount: coverage.covered,
            totalCount: coverage.total,
            totalValueText: dominantCurrencyTotalText(for: records),
            totalValueCompactText: dominantCurrencyTotalCompactText(for: records),
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
        guard let dominant = dominantCurrencyTotal(for: records) else { return nil }
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
        let amountText = formatter.string(from: NSNumber(value: dominant.amount)) ?? "\(Int(dominant.amount))"
        return "\(dominant.currency) \(amountText)"
    }

    /// Same dominant-currency total as `dominantCurrencyTotalText`, but
    /// abbreviated for tight widget layouts (the coverage-ring small
    /// widget's caption line) — e.g. `"S$3.1k"` instead of `"SGD 3,116"`,
    /// which was truncating there. `compactCurrencySymbols` is a small,
    /// fixed table (not the device locale) so this stays deterministic
    /// across devices, same rationale as the long form; falls back to the
    /// raw ISO code for anything unmapped.
    nonisolated static func dominantCurrencyTotalCompactText(for records: [PurchaseRecord]) -> String? {
        guard let dominant = dominantCurrencyTotal(for: records) else { return nil }
        let symbol = compactCurrencySymbols[dominant.currency] ?? dominant.currency
        return "\(symbol)\(compactAmountText(dominant.amount))"
    }

    /// The currency with the largest summed `amount` across `records`
    /// (records with no `amount` are skipped; a `nil` `currency` defaults
    /// to `"SGD"`), shared by both the long and compact total-text
    /// formatters. Ties broken alphabetically for determinism — see
    /// `dominantCurrencyTotalText`'s doc for the comparator rationale.
    private nonisolated static func dominantCurrencyTotal(for records: [PurchaseRecord]) -> (currency: String, amount: Double)? {
        var totalsByCurrency: [String: Double] = [:]
        for record in records {
            guard let amount = record.amount else { continue }
            let currency = record.currency ?? "SGD"
            totalsByCurrency[currency, default: 0] += amount
        }
        guard let dominant = totalsByCurrency.max(by: { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }) else { return nil }
        return (dominant.key, dominant.value)
    }

    /// ISO 4217 code → a short display symbol for the compact widget total
    /// only — never used for money math or the long-form text, which stays
    /// in explicit-code form. Deliberately a fixed table, not locale-derived.
    private static let compactCurrencySymbols: [String: String] = [
        "USD": "$", "SGD": "S$", "EUR": "€", "GBP": "£", "JPY": "¥",
        "CNY": "¥", "AUD": "A$", "CAD": "C$", "NZD": "NZ$", "HKD": "HK$",
        "INR": "₹", "KRW": "₩", "CHF": "CHF",
    ]

    /// "842", "3.1k", "1.2m" — one decimal place above 1,000, none below,
    /// trailing ".0" trimmed. `en_US_POSIX`-pinned like the rest of this
    /// file, for the same cross-device determinism reason.
    nonisolated static func compactAmountText(_ value: Double) -> String {
        let absValue = abs(value)
        let (scaled, suffix): (Double, String) =
            absValue >= 1_000_000 ? (value / 1_000_000, "m")
            : absValue >= 1_000 ? (value / 1_000, "k")
            : (value, "")
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = suffix.isEmpty ? 0 : 1
        formatter.minimumFractionDigits = 0
        let numberText = formatter.string(from: NSNumber(value: scaled)) ?? "\(Int(scaled))"
        return "\(numberText)\(suffix)"
    }

    /// The first unregistered, *recently purchased* item whose warranty is
    /// still active — the "Closing soon" widget's gold nudge row. "Recent"
    /// means purchased within the last 30 days (day granularity,
    /// BUILD_REVIEW W1): nudging registration of a year-old appliance is
    /// manufactured urgency, and a record with no `purchaseDate` can't
    /// prove it's fresh, so it never qualifies. Deterministic ordering:
    /// soonest-expiring first, then display name — mirrors
    /// `DigestBuilder.build`'s sort for the same underlying condition
    /// (`!isRegistered && warranty not yet expired`). `nil` when nothing
    /// qualifies. Name is the display form (`displayProductName`, B5) so
    /// the widget never shouts a raw OCR string.
    nonisolated static func registerNudgeCandidate(
        for records: [PurchaseRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WidgetRegisterNudge? {
        let today = calendar.startOfDay(for: now)
        let candidates: [(record: PurchaseRecord, daysLeft: Int)] = records.compactMap { record in
            guard !record.isRegistered, let expiry = record.warrantyExpiryDate else { return nil }
            guard let purchaseDate = record.purchaseDate else { return nil }
            let purchaseDay = calendar.startOfDay(for: purchaseDate)
            let daysSincePurchase = calendar.dateComponents([.day], from: purchaseDay, to: today).day ?? 0
            guard daysSincePurchase <= 30 else { return nil }
            let expiryDay = calendar.startOfDay(for: expiry)
            guard expiryDay >= today else { return nil }
            let daysLeft = calendar.dateComponents([.day], from: today, to: expiryDay).day ?? 0
            return (record, daysLeft)
        }
        let sorted = candidates.sorted {
            $0.daysLeft != $1.daysLeft ? $0.daysLeft < $1.daysLeft : $0.record.displayProductName < $1.record.displayProductName
        }
        guard let first = sorted.first else { return nil }
        return WidgetRegisterNudge(recordID: first.record.id, name: first.record.displayProductName)
    }
}

extension PurchaseRecord {
    /// This record's candidate widget events — a warranty-expiry entry
    /// and/or a return-deadline entry, whichever are tracked. Not yet
    /// filtered for past dates or trimmed to a limit; that's
    /// `WidgetSnapshotWriter.nearestUpcoming`'s job. Mirrors the shape of
    /// `digestSnapshot` in `DigestScheduler.swift`. Names are the display
    /// form (`displayProductName`, BUILD_REVIEW B5) so widgets never shout
    /// a raw OCR string — the raw `productName` stays on the record.
    nonisolated var widgetCandidates: [WidgetSnapshotItem] {
        var items: [WidgetSnapshotItem] = []
        if let warrantyExpiryDate {
            items.append(WidgetSnapshotItem(recordID: id, name: displayProductName, kind: "warranty", date: warrantyExpiryDate))
        }
        if let returnDeadline {
            items.append(WidgetSnapshotItem(recordID: id, name: displayProductName, kind: "return", date: returnDeadline))
        }
        return items
    }
}
