import Foundation

/// The one remaining-time formatter for coverage deadlines — app, widgets,
/// and notifications all phrase "how long is left" through these rules so
/// the same number never renders as "321 days", "321d", and "10 mo" on
/// different surfaces (BUILD_REVIEW W2).
///
/// Rules:
/// - ≥ 90 days left → months: "10 mo"
/// - 8–89 days → "34 days"
/// - ≤ 7 days → "6 days" (amber context is the caller's job)
/// - last day → "today"
/// - past → "expired"
/// Absolute dates include the year whenever the date is more than 6 months
/// out from the reference day: "3 Jun 2027", but "3 Jun" for a near date
/// (BUILD_REVIEW W7).
///
/// The widget extension has no shared framework with the app target, so it
/// keeps a byte-identical mirror in `PaperTrailWidgets/CoverageFormatter.swift`
/// — same rule as `WidgetSnapshot`; change both or neither.
enum CoverageFormatter {
    /// Whole-day difference anchored to start-of-day, so the phrase doesn't
    /// depend on time-of-day. Negative once the date has passed.
    static func daysLeft(from asOf: Date, to date: Date, calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: asOf)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// "10 mo", "34 days", "6 days", "1 day", "today", "expired".
    static func remaining(days: Int) -> String {
        if days < 0 { return "expired" }
        if days == 0 { return "today" }
        if days == 1 { return "1 day" }
        if days < 90 { return "\(days) days" }
        return "\(days / 30) mo"
    }

    /// "10 mo left", "34 days left" — with "today"/"expired" left alone,
    /// because "today left" isn't a phrase.
    static func remainingLeft(days: Int) -> String {
        let phrase = remaining(days: days)
        return days <= 0 ? phrase : "\(phrase) left"
    }

    /// "4 mo ago", "12 days ago" for a past date; "today" for today. Same
    /// unit thresholds as `remaining(days:)`, just pointed backwards.
    static func past(daysAgo days: Int) -> String {
        if days <= 0 { return "today" }
        return "\(remaining(days: days)) ago"
    }

    /// "3 Jun" when the date is within ±6 months of `asOf`, "3 Jun 2027"
    /// beyond that — a far-out date without a year is ambiguous
    /// (BUILD_REVIEW W7). Locale-pinned so widget snapshots and app copy
    /// agree across devices/regions.
    static func absoluteDate(_ date: Date, asOf: Date = .now, calendar: Calendar = .current) -> String {
        let days = abs(daysLeft(from: asOf, to: date, calendar: calendar))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = days > 183 ? "d MMM yyyy" : "d MMM"
        return formatter.string(from: date)
    }

    /// "Jun 2027" — the month-year form used by quiet/portfolio lines
    /// ("next: Jun 2027").
    static func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}
