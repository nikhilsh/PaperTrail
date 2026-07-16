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
    var id: UUID
    var name: String
    /// "warranty" or "return"
    var kind: String
    var date: Date
}

/// The full snapshot written to the App Group container.
struct WidgetSnapshot: Codable, Sendable {
    var generatedAt: Date
    var items: [WidgetSnapshotItem]
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
    /// `AppShellView`.
    static func write(modelContext: ModelContext) {
        let records: [PurchaseRecord]
        do {
            records = try modelContext.fetch(FetchDescriptor<PurchaseRecord>())
        } catch {
            AppLogger.error("Widget snapshot fetch failed: \(error.localizedDescription)", category: "widget")
            return
        }

        let candidates = records.flatMap(\.widgetCandidates)
        let items = nearestUpcoming(from: candidates, limit: maxItems)
        let snapshot = WidgetSnapshot(generatedAt: .now, items: items)

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
        } catch {
            AppLogger.error("Widget snapshot write failed: \(error.localizedDescription)", category: "widget")
            return
        }

        WidgetCenter.shared.reloadAllTimelines()
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
            items.append(WidgetSnapshotItem(id: id, name: productName, kind: "warranty", date: warrantyExpiryDate))
        }
        if let returnDeadline {
            items.append(WidgetSnapshotItem(id: id, name: productName, kind: "return", date: returnDeadline))
        }
        return items
    }
}
