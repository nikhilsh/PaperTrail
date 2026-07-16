import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct ExpiringSoonEntry: TimelineEntry {
    let date: Date
    let items: [WidgetSnapshotItem]
}

// MARK: - Provider

/// Reads the App Group JSON snapshot the app writes on every foreground —
/// never touches SwiftData/CloudKit directly (CLAUDE.md high-risk rule: the
/// widget target must stay off the store). Missing container, missing file,
/// or undecodable JSON all fall back to an empty snapshot rather than
/// crashing the widget.
struct ExpiringSoonProvider: TimelineProvider {
    private static let appGroupIdentifier = "group.nikhilsh.PaperTrail"
    private static let snapshotFileName = "widget-snapshot.json"

    func placeholder(in context: Context) -> ExpiringSoonEntry {
        ExpiringSoonEntry(date: .now, items: Self.placeholderItems)
    }

    func getSnapshot(in context: Context, completion: @escaping (ExpiringSoonEntry) -> Void) {
        let items = context.isPreview ? Self.placeholderItems : Self.readSnapshot().items
        completion(ExpiringSoonEntry(date: .now, items: items))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExpiringSoonEntry>) -> Void) {
        let items = Self.readSnapshot().items
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
            ExpiringSoonEntry(date: now, items: items),
            ExpiringSoonEntry(date: nextMidnight, items: items),
        ]
        completion(Timeline(entries: entries, policy: .after(nextMidnight)))
    }

    private static func readSnapshot() -> WidgetSnapshot {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return WidgetSnapshot(generatedAt: .now, items: [])
        }
        let fileURL = containerURL.appendingPathComponent(snapshotFileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            return WidgetSnapshot(generatedAt: .now, items: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot(generatedAt: .now, items: [])
        }
        return snapshot
    }

    private static var placeholderItems: [WidgetSnapshotItem] {
        [
            WidgetSnapshotItem(
                id: UUID(),
                name: "Sample Warranty",
                kind: "warranty",
                date: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
            ),
        ]
    }
}

// MARK: - Day-count formatting

private enum ExpiringSoonFormatting {
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
        URL(string: "papertrail://record/\(item.id.uuidString)")
    }
}

// MARK: - Views

/// Shown when there's no upcoming warranty/return to surface — an empty
/// snapshot, a missing App Group container, or an unreadable file all land
/// here rather than crashing the widget.
private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("PaperTrail")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WidgetPalette.gold)
            Text("Nothing expiring soon")
                .font(.footnote)
                .foregroundStyle(WidgetPalette.cream)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(WidgetPalette.background, for: .widget)
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
            EmptyStateView()
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
            EmptyStateView()
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
                Text(ExpiringSoonFormatting.lockScreenPhrase(daysLeft))
                    .font(.caption)
            }
            .containerBackground(.clear, for: .widget)
        } else {
            Text("Nothing expiring soon")
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
