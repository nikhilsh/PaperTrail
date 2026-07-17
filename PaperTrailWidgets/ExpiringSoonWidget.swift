import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct ExpiringSoonEntry: TimelineEntry {
    let date: Date
    let items: [WidgetSnapshotItem]
    /// `false` when the App Group snapshot was missing, undecodable, or the
    /// container itself was unreachable — as opposed to `true` with empty
    /// `items`, which means the snapshot decoded fine and there's genuinely
    /// nothing upcoming. The two used to be indistinguishable and both
    /// rendered "Nothing expiring soon", which is a false reassurance when
    /// the widget actually just can't see the app's data.
    let isDataAvailable: Bool

    // MARK: v3 shelfWidgets fields
    //
    // Carried on the same entry as `items`/`isDataAvailable` rather than a
    // separate provider/entry type — `ExpiringSoonProvider` already reads
    // and decodes the one App Group snapshot; the shelf widgets
    // (`ShelfWidgets.swift`) reuse this same provider so there's only one
    // snapshot-loading path in the extension. `ExpiringSoonWidgetView`
    // (the pre-v3 widget) ignores these — its rendering is unconditional,
    // flag-independent v2 behavior.
    let coveredCount: Int?
    let totalCount: Int?
    let totalValueText: String?
    /// Abbreviated form of `totalValueText` (e.g. "S$3.1k" vs "SGD 3,116")
    /// for tight widget layouts — see `WidgetSnapshot.totalValueCompactText`.
    let totalValueCompactText: String?
    let registerNudge: WidgetRegisterNudge?
}

// MARK: - Provider

/// Reads the App Group JSON snapshot the app writes on every foreground —
/// never touches SwiftData/CloudKit directly (CLAUDE.md high-risk rule: the
/// widget target must stay off the store). Missing container, missing file,
/// or undecodable JSON never crash the widget — they fall back to an empty
/// item list, same as a snapshot that decoded fine with nothing upcoming,
/// but are flagged via `ExpiringSoonEntry.isDataAvailable` so the two don't
/// render the same "nothing to worry about" copy.
struct ExpiringSoonProvider: TimelineProvider {
    private static let appGroupIdentifier = "group.nikhilsh.PaperTrail"
    private static let snapshotFileName = "widget-snapshot.json"

    func placeholder(in context: Context) -> ExpiringSoonEntry {
        Self.entry(date: .now, items: Self.placeholderItems, isDataAvailable: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ExpiringSoonEntry) -> Void) {
        if context.isPreview {
            completion(Self.entry(date: .now, items: Self.placeholderItems, isDataAvailable: true))
            return
        }
        let snapshot = Self.readSnapshot()
        completion(Self.entry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExpiringSoonEntry>) -> Void) {
        let snapshot = Self.readSnapshot()
        let now = Date.now
        let calendar = Calendar.current
        let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(86_400)

        // Two entries — now and next midnight — so the "Nd left" day count
        // ticks over at day boundaries without needing an app-triggered
        // reload; `.after(nextMidnight)` asks WidgetKit for a fresh timeline
        // once that entry is stale.
        let entries = [
            Self.entry(date: now, snapshot: snapshot),
            Self.entry(date: nextMidnight, snapshot: snapshot),
        ]
        completion(Timeline(entries: entries, policy: .after(nextMidnight)))
    }

    /// `nil` covers every "can't tell" case (no container, no file,
    /// undecodable JSON) — collapsed to `isDataAvailable: false` by the
    /// caller, distinct from a snapshot that decoded fine with zero items.
    private static func readSnapshot() -> WidgetSnapshot? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        let fileURL = containerURL.appendingPathComponent(snapshotFileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Builds an entry directly from a decoded (or missing) snapshot,
    /// carrying the v3 fields through unconditionally — `nil` on a
    /// pre-v3/undecodable snapshot exactly like a missing App Group file
    /// does, no separate "can't tell" path needed for those.
    private static func entry(date: Date, snapshot: WidgetSnapshot?) -> ExpiringSoonEntry {
        entry(
            date: date,
            items: snapshot?.items ?? [],
            isDataAvailable: snapshot != nil,
            coveredCount: snapshot?.coveredCount,
            totalCount: snapshot?.totalCount,
            totalValueText: snapshot?.totalValueText,
            totalValueCompactText: snapshot?.totalValueCompactText,
            registerNudge: snapshot?.registerNudge
        )
    }

    private static func entry(
        date: Date,
        items: [WidgetSnapshotItem],
        isDataAvailable: Bool,
        coveredCount: Int? = nil,
        totalCount: Int? = nil,
        totalValueText: String? = nil,
        totalValueCompactText: String? = nil,
        registerNudge: WidgetRegisterNudge? = nil
    ) -> ExpiringSoonEntry {
        ExpiringSoonEntry(
            date: date,
            items: items,
            isDataAvailable: isDataAvailable,
            coveredCount: coveredCount,
            totalCount: totalCount,
            totalValueText: totalValueText,
            totalValueCompactText: totalValueCompactText,
            registerNudge: registerNudge
        )
    }

    private static var placeholderItems: [WidgetSnapshotItem] {
        [
            WidgetSnapshotItem(
                recordID: UUID(),
                name: "Sample Warranty",
                kind: "warranty",
                date: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
            ),
        ]
    }
}

// MARK: - Day-count formatting

// Internal (not `private`) — `ShelfWidgets.swift`'s v3 widgets reuse
// `daysLeft`/`deepLink` rather than re-deriving the same day-math and
// deep-link logic. (Their remaining-time *phrasing* routes through
// `CoverageFormatter` instead — the compact "6d"/"3d left" forms here are
// v2-only, and this v2 surface is APPSTORE-frozen.)
enum ExpiringSoonFormatting {
    /// Whole-day difference from `asOf` to `date`, anchored to start-of-day
    /// so it doesn't depend on time-of-day. Negative once the date has
    /// passed.
    static func daysLeft(from asOf: Date, to date: Date, calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: asOf)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Compact big-number label: "3d", "today", "expired".
    static func bigLabel(_ daysLeft: Int) -> String {
        if daysLeft < 0 { return "expired" }
        if daysLeft == 0 { return "today" }
        return "\(daysLeft)d"
    }

    /// Lock Screen phrasing: "3d left", "Today", "Expired".
    static func lockScreenPhrase(_ daysLeft: Int) -> String {
        if daysLeft < 0 { return "Expired" }
        if daysLeft == 0 { return "Today" }
        return "\(daysLeft)d left"
    }

    static func color(_ daysLeft: Int) -> Color {
        if daysLeft <= 0 { return WidgetPalette.terra }
        if daysLeft <= 7 { return WidgetPalette.amber }
        return WidgetPalette.gold
    }

    static func kindLabel(_ kind: String) -> String {
        kind == "return" ? "RETURN" : "WARRANTY"
    }

    static func deepLink(for item: WidgetSnapshotItem) -> URL? {
        URL(string: "papertrail://record/\(item.recordID.uuidString)")
    }
}

// MARK: - Views

/// Shown when there's no item to surface — either a genuinely empty
/// snapshot ("Nothing expiring soon") or a missing/undecodable snapshot or
/// unreachable App Group container ("Open PaperTrail to update"), never
/// crashing the widget either way. Which message applies is the caller's
/// call, driven by `ExpiringSoonEntry.isDataAvailable`.
// Part of the pixel-frozen v2 APPSTORE surface — the v3 dark "Next up"
// widget used to reuse this but now has its own `NextUpEmptyStateView`
// (W6 chrome), precisely so this one never has to change.
struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 4) {
            Text("PaperTrail")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WidgetPalette.gold)
            Text(message)
                .font(.footnote)
                .foregroundStyle(WidgetPalette.cream)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(WidgetPalette.background, for: .widget)
    }
}

// Internal (not `private`) — `ShelfWidgets.swift` reuses `emptyStateMessage`
// so the "nothing to show" copy stays identical between the v2 widget and
// the v3 shelf widgets.
extension ExpiringSoonEntry {
    var emptyStateMessage: String {
        isDataAvailable ? "Nothing expiring soon" : "Open PaperTrail to update"
    }
}

private struct SmallWidgetView: View {
    let entry: ExpiringSoonEntry

    var body: some View {
        if let item = entry.items.first {
            let daysLeft = ExpiringSoonFormatting.daysLeft(from: entry.date, to: item.date)
            VStack(alignment: .leading, spacing: 8) {
                Text(ExpiringSoonFormatting.kindLabel(item.kind))
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(WidgetPalette.gold)

                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()

                Spacer(minLength: 0)

                Text(ExpiringSoonFormatting.bigLabel(daysLeft))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(ExpiringSoonFormatting.color(daysLeft))
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(WidgetPalette.background, for: .widget)
            .widgetURL(ExpiringSoonFormatting.deepLink(for: item))
        } else {
            EmptyStateView(message: entry.emptyStateMessage)
        }
    }
}

private struct MediumWidgetRow: View {
    let item: WidgetSnapshotItem
    let asOf: Date

    var body: some View {
        let daysLeft = ExpiringSoonFormatting.daysLeft(from: asOf, to: item.date)
        let destination = ExpiringSoonFormatting.deepLink(for: item)

        let row = HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WidgetPalette.cream)
                    .lineLimit(1)
                    .privacySensitive()
                Text(ExpiringSoonFormatting.kindLabel(item.kind))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(WidgetPalette.gold.opacity(0.8))
            }
            Spacer(minLength: 8)
            Text(ExpiringSoonFormatting.bigLabel(daysLeft))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ExpiringSoonFormatting.color(daysLeft))
        }

        if let destination {
            Link(destination: destination) { row }
        } else {
            row
        }
    }
}

private struct MediumWidgetView: View {
    let entry: ExpiringSoonEntry

    var body: some View {
        if entry.items.isEmpty {
            EmptyStateView(message: entry.emptyStateMessage)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entry.items.prefix(3)) { item in
                    MediumWidgetRow(item: item, asOf: entry.date)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(WidgetPalette.background, for: .widget)
        }
    }
}

private struct AccessoryRectangularView: View {
    let entry: ExpiringSoonEntry

    var body: some View {
        if let item = entry.items.first {
            let daysLeft = ExpiringSoonFormatting.daysLeft(from: entry.date, to: item.date)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                    .privacySensitive()
                Text(ExpiringSoonFormatting.lockScreenPhrase(daysLeft))
                    .font(.caption)
            }
            .containerBackground(.clear, for: .widget)
        } else {
            Text(entry.emptyStateMessage)
                .font(.caption)
                .containerBackground(.clear, for: .widget)
        }
    }
}

struct ExpiringSoonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ExpiringSoonProvider.Entry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget

struct ExpiringSoonWidget: Widget {
    let kind: String = "ExpiringSoonWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExpiringSoonProvider()) { entry in
            ExpiringSoonWidgetView(entry: entry)
        }
        .configurationDisplayName("Expiring Soon")
        .description("Warranties and return windows that need attention.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
