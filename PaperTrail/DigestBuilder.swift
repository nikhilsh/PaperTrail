import Foundation

/// Plain value snapshot of the fields `DigestBuilder` needs from a
/// `PurchaseRecord`. Decoupled from SwiftData/CloudKit on purpose: the
/// builder stays a pure, nonisolated, trivially-testable function with no
/// `ModelContext` dependency. Callers (the in-app card, the notification
/// scheduler) map their live records into this shape.
struct DigestRecordSnapshot: Sendable {
    var productName: String
    var warrantyExpiryDate: Date?
    var amount: Double?
    var currency: String?
    /// End-of-day deadline for a tracked return/refund window. Mirrors
    /// `PurchaseRecord.returnDeadline` — already resolved, not recomputed here.
    var returnDeadline: Date?
    var isRegistered: Bool

    init(
        productName: String,
        warrantyExpiryDate: Date? = nil,
        amount: Double? = nil,
        currency: String? = nil,
        returnDeadline: Date? = nil,
        isRegistered: Bool = false
    ) {
        self.productName = productName
        self.warrantyExpiryDate = warrantyExpiryDate
        self.amount = amount
        self.currency = currency
        self.returnDeadline = returnDeadline
        self.isRegistered = isRegistered
    }
}

/// One line in a "soonest" list: an item name and how many days remain.
struct DigestUpcomingItem: Equatable, Sendable {
    let name: String
    let daysLeft: Int
}

/// A per-currency total across the warranties expiring soon — separate
/// totals rather than one converted number, since PaperTrail never converts
/// currencies.
struct DigestCurrencyTotal: Equatable, Sendable {
    let currency: String
    let amount: Double
}

/// The monthly coverage digest: what's expiring, what's closing, and what's
/// exposed because it was never registered. Feeds both the push notification
/// body and the in-app "This month" card, so the two always agree.
struct DigestSummary: Equatable, Sendable {
    var expiringWarrantyCount: Int = 0
    var expiringWarrantyTotals: [DigestCurrencyTotal] = []
    /// Up to 3 soonest-expiring warranties, soonest first.
    var soonestExpiring: [DigestUpcomingItem] = []

    var closingReturnCount: Int = 0
    var soonestClosingReturn: DigestUpcomingItem?

    var unregisteredActiveCount: Int = 0

    /// True when there is nothing worth telling the user this month — the
    /// scheduler skips notifying (and clears any pending one) in this case.
    /// Unregistered items deliberately don't count: registration nudges have
    /// their own surfaces (widget, record rows) — a month where they're the
    /// only news is a quiet month, not a reason to nag (device feedback,
    /// build 40).
    var isEmpty: Bool {
        expiringWarrantyCount == 0 && closingReturnCount == 0
    }

    /// One-line summary, e.g. "3 warranties end within 60 days (SGD 4,200 of
    /// coverage) · 1 return window closes tomorrow". Empty parts are omitted
    /// entirely; singular/plural nouns are handled per-part. Currency totals
    /// are rendered as "<code> <amount>" (not a locale currency symbol) so
    /// the string is deterministic across devices/locales.
    var headline: String {
        var parts: [String] = []

        if expiringWarrantyCount > 0 {
            let noun = expiringWarrantyCount == 1 ? "warranty ends" : "warranties end"
            var clause = "\(expiringWarrantyCount) \(noun) within 60 days"
            if !expiringWarrantyTotals.isEmpty {
                clause += " (\(DigestSummary.totalsText(expiringWarrantyTotals)) of coverage)"
            }
            parts.append(clause)
        }

        if closingReturnCount > 0, let soonest = soonestClosingReturn {
            let noun = closingReturnCount == 1 ? "return window closes" : "return windows close"
            parts.append("\(closingReturnCount) \(noun) \(DigestSummary.dayLabel(daysLeft: soonest.daysLeft))")
        }

        return parts.joined(separator: " · ")
    }

    /// Short headline for the push-notification body — no currency totals
    /// (a lock-screen isn't the place to broadcast a household's coverage
    /// value) and no day-precision phrasing ("today"/"tomorrow"/"in N days",
    /// which goes stale between when the digest is scheduled and whenever
    /// the user actually reads the notification). e.g. "3 warranties end
    /// soon · 1 return window is closing". The in-app card keeps the full
    /// `headline`.
    var notificationHeadline: String {
        var parts: [String] = []

        if expiringWarrantyCount > 0 {
            let noun = expiringWarrantyCount == 1 ? "warranty ends soon" : "warranties end soon"
            parts.append("\(expiringWarrantyCount) \(noun)")
        }

        if closingReturnCount > 0 {
            let noun = closingReturnCount == 1 ? "return window is closing" : "return windows are closing"
            parts.append("\(closingReturnCount) \(noun)")
        }

        return parts.joined(separator: " · ")
    }

    private static func dayLabel(daysLeft: Int) -> String {
        switch daysLeft {
        case 0: return "today"
        case 1: return "tomorrow"
        default: return "in \(daysLeft) days"
        }
    }

    private static func totalsText(_ totals: [DigestCurrencyTotal]) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return totals.map { total in
            let numberText = formatter.string(from: NSNumber(value: total.amount)) ?? "\(Int(total.amount))"
            return "\(total.currency) \(numberText)"
        }.joined(separator: " + ")
    }
}

/// Pure, nonisolated builder: value snapshots in, `DigestSummary` out. No
/// SwiftData, no notification APIs — safe to unit test directly.
enum DigestBuilder {
    static let expiringWarrantyWindowDays = 60
    static let closingReturnWindowDays = 7

    /// Builds the digest as of `now`. `now`/`calendar` are injectable so
    /// tests can pin exact day-boundary behavior instead of racing the clock.
    static func build(
        from records: [DigestRecordSnapshot],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DigestSummary {
        var summary = DigestSummary()

        // Warranties expiring within the next 60 days (not already expired).
        let expiring: [(record: DigestRecordSnapshot, daysLeft: Int)] = records.compactMap { record in
            guard let expiry = record.warrantyExpiryDate,
                  let days = daysBetween(now, expiry, calendar: calendar),
                  days >= 0, days <= expiringWarrantyWindowDays else { return nil }
            return (record, days)
        }
        let sortedExpiring = expiring.sorted {
            $0.daysLeft != $1.daysLeft ? $0.daysLeft < $1.daysLeft : $0.record.productName < $1.record.productName
        }
        summary.expiringWarrantyCount = sortedExpiring.count
        summary.expiringWarrantyTotals = totals(for: sortedExpiring.map(\.record))
        summary.soonestExpiring = sortedExpiring.prefix(3).map {
            DigestUpcomingItem(name: $0.record.productName, daysLeft: $0.daysLeft)
        }

        // Return windows closing within the next 7 days (not already closed).
        let closing: [(record: DigestRecordSnapshot, daysLeft: Int)] = records.compactMap { record in
            guard let deadline = record.returnDeadline,
                  let days = daysBetween(now, deadline, calendar: calendar),
                  days >= 0, days <= closingReturnWindowDays else { return nil }
            return (record, days)
        }
        let sortedClosing = closing.sorted {
            $0.daysLeft != $1.daysLeft ? $0.daysLeft < $1.daysLeft : $0.record.productName < $1.record.productName
        }
        summary.closingReturnCount = sortedClosing.count
        summary.soonestClosingReturn = sortedClosing.first.map {
            DigestUpcomingItem(name: $0.record.productName, daysLeft: $0.daysLeft)
        }

        // Unregistered items whose warranty hasn't expired yet, regardless of
        // whether they fall inside the 60-day expiring window. Compared at
        // day granularity — matching `daysBetween` above — so a warranty
        // expiring today counts as still active here just like it counts in
        // the expiring list.
        summary.unregisteredActiveCount = records.filter { record in
            guard !record.isRegistered, let expiry = record.warrantyExpiryDate else { return false }
            return calendar.startOfDay(for: expiry) >= calendar.startOfDay(for: now)
        }.count

        return summary
    }

    /// Whole-day difference between two dates, anchored to the start of each
    /// day so the boundary doesn't depend on time-of-day.
    private static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int? {
        let fromDay = calendar.startOfDay(for: from)
        let toDay = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: fromDay, to: toDay).day
    }

    private static func totals(for records: [DigestRecordSnapshot]) -> [DigestCurrencyTotal] {
        var byCurrency: [String: Double] = [:]
        for record in records {
            guard let amount = record.amount else { continue }
            let currency = record.currency ?? "SGD"
            byCurrency[currency, default: 0] += amount
        }
        return byCurrency
            .map { DigestCurrencyTotal(currency: $0.key, amount: $0.value) }
            .sorted { $0.currency < $1.currency }
    }
}
