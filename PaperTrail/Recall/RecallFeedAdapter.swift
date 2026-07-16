import Foundation

/// A single safety recall/advisory notice, as surfaced by a `RecallFeedAdapter`.
///
/// `nonisolated`: pure value data, no UI/actor state — same reasoning as
/// `CoverageLine`/`ServiceEntry` (the project defaults declarations to
/// `@MainActor` via `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and this is
/// constructed directly in tests off the main actor).
nonisolated struct RecallNotice: Codable, Hashable, Identifiable, Sendable {
    /// Stable identifier from the feed (not a local UUID) — used both for
    /// `Identifiable` and to remember which specific notice a record last
    /// matched (`RecallWatcher`'s persisted per-record result).
    var id: String
    var brand: String
    /// Model numbers/name fragments this notice applies to. Matched against
    /// a record's serial number and product name — see `RecallMatcher`.
    /// Empty means "applies to every product from this brand".
    var modelPatterns: [String]
    var title: String
    var detailURL: URL
    var date: Date
}

/// Source of recall notices for `RecallWatcher` to match records against.
/// One implementation per feed; `RecallWatcher` doesn't care which.
protocol RecallFeedAdapter: Sendable {
    /// `true` when this feed's notices are hand-curated fixture data rather
    /// than a real recall source. `RecallWatcher` uses this to (a) never
    /// fire a real safety notification off fixture data, and
    /// `RecordDetailView`'s recall row uses it to (b) never present a
    /// fixture match as a genuine recall — both are load-bearing honesty
    /// guards, not cosmetic. See `FixtureRecallFeed`.
    var isFixture: Bool { get }
    func fetchRecalls() async throws -> [RecallNotice]
}

/// Reads the bundled `recall-fixtures.json` — a small, hand-curated set of
/// realistic-shaped recall notices (generic titles, no real-company
/// defamation) so `recallWatch` has something to match against before real
/// feed sourcing is decided.
///
/// **Follow-up (V3_BRIEF §6):** real sourcing is CPSC + local-market
/// equivalents, fetched over the network. This adapter is deliberately the
/// only thing that needs to change when that's built — `RecallWatcher` talks
/// to the `RecallFeedAdapter` protocol, not to fixture data directly.
struct FixtureRecallFeed: RecallFeedAdapter {
    enum FeedError: Error {
        case resourceNotFound
    }

    /// Always `true` — every notice this feed returns is fixture data, not
    /// a real recall. See the protocol doc for why this matters.
    let isFixture = true

    /// `Bundle` is injectable so tests can point at `Bundle.module`/a test
    /// bundle rather than depending on `Bundle.main` (which isn't
    /// necessarily the test runner's bundle).
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func fetchRecalls() async throws -> [RecallNotice] {
        guard let url = bundle.url(forResource: "recall-fixtures", withExtension: "json") else {
            throw FeedError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([RecallNotice].self, from: data)
    }
}
