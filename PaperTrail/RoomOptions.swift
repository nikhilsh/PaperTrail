import Foundation

/// The room/location a purchased item lives in (distinct from `category`, which
/// is *what* the item is). The list behaves like a growable enum: a small set of
/// defaults plus every custom room the user has already used — so a one-off
/// "Wine Cellar" becomes a permanent choice without any separate list to manage.
enum RoomOptions {

    /// Minimal seed set. Custom rooms accumulate on top of these via the records.
    static let defaults = ["Living Room", "Bedroom", "Kitchen", "Office", "Other"]

    /// Defaults unioned with rooms already present on existing records,
    /// de-duplicated (case-insensitively) and sorted for a stable picker.
    static func suggestions(existing: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for room in defaults + existing {
            let trimmed = room.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
