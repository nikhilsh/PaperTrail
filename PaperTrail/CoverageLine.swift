import Foundation

/// A single named coverage line on the Coverage Passport's "What's covered"
/// group (docs/design-v2/V2_BRIEF.md §2, W2) — e.g. "Accidental damage" ✓,
/// "Water damage" ✗. User-entered from what the warranty card actually says;
/// distinct from the free-text `coverageSummary` already on `PurchaseRecord`.
///
/// Backed by `PurchaseRecord.coverageLinesData` (small JSON blob) via the
/// `coverageLines` computed property — see the schema-risk note there.
///
/// `nonisolated`: pure value data, no UI/actor state — the project defaults
/// declarations to `@MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)
/// and this is constructed directly in tests off the main actor.
nonisolated struct CoverageLine: Codable, Hashable {
    var label: String
    var covered: Bool
}
