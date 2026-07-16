import Foundation

/// Mirrors `PaperTrail/WidgetSnapshot.swift`. The widget extension has no
/// access to the app target's sources (no shared framework between the two
/// targets), so this is a deliberately duplicated copy of the App Group JSON
/// contract — keep the two in sync if the shape ever changes.
struct WidgetSnapshotItem: Codable, Sendable, Identifiable {
    var id: UUID
    var name: String
    /// "warranty" or "return"
    var kind: String
    var date: Date
}

struct WidgetSnapshot: Codable, Sendable {
    var generatedAt: Date
    var items: [WidgetSnapshotItem]
}
