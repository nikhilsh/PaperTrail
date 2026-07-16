import Foundation

/// Mirrors `PaperTrail/WidgetSnapshot.swift`. The widget extension has no
/// access to the app target's sources (no shared framework between the two
/// targets), so this is a deliberately duplicated copy of the App Group JSON
/// contract — keep the two in sync if the shape ever changes.
struct WidgetSnapshotItem: Codable, Sendable, Identifiable {
    /// The `PurchaseRecord` this event belongs to — what the widget's deep
    /// links resolve to (`papertrail://record/<recordID>`).
    var recordID: UUID
    var name: String
    /// "warranty" or "return"
    var kind: String
    var date: Date

    /// A single record can produce both a "warranty" and a "return" event —
    /// `recordID` alone collided as `Identifiable` `id` and caused SwiftUI
    /// `ForEach`/List identity clashes in the widget. Computed, not stored,
    /// so it's never out of sync with `recordID`/`kind` and doesn't
    /// duplicate them in the JSON.
    var id: String { "\(recordID)-\(kind)" }
}

struct WidgetSnapshot: Codable, Sendable {
    var generatedAt: Date
    var items: [WidgetSnapshotItem]
}
