import WidgetKit
import SwiftUI

struct ExpiringSoonEntry: TimelineEntry {
    let date: Date
}

struct ExpiringSoonProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExpiringSoonEntry {
        ExpiringSoonEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (ExpiringSoonEntry) -> Void) {
        completion(ExpiringSoonEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExpiringSoonEntry>) -> Void) {
        let entry = ExpiringSoonEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct ExpiringSoonWidgetView: View {
    var entry: ExpiringSoonProvider.Entry

    var body: some View {
        VStack(spacing: 4) {
            Text("PaperTrail")
                .font(.headline)
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct ExpiringSoonWidget: Widget {
    let kind: String = "ExpiringSoonWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExpiringSoonProvider()) { entry in
            ExpiringSoonWidgetView(entry: entry)
        }
        .configurationDisplayName("PaperTrail")
        .description("See warranties expiring soon.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
