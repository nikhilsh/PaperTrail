import Foundation

/// A single named coverage line on the Coverage Passport's "What's covered"
/// group (docs/design-v2/V2_BRIEF.md §2, W2) — e.g. "Accidental damage" ✓,
/// "Water damage" ✗. User-entered from what the warranty card actually says;
/// distinct from the free-text `coverageSummary` already on `PurchaseRecord`.
///
/// Backed by `PurchaseRecord.coverageLinesData` (small JSON blob) via the
/// `coverageLines` computed property — see the schema-risk note there.
///
/// v3 `multiCoverage` (docs/design-v3/V3_BRIEF.md §2) adds `startDate`,
/// `endDate`, `kind`, and `coveredItems`; the same wave that added `id`
/// (Identifiable, for `ForEach`/list diffing) added it — all additive-only
/// per CLAUDE.md's CloudKit schema rules. `init(from:)` below defaults any
/// missing key (including `id`) rather than failing to decode, so pre-v3
/// JSON (`{"label":...,"covered":...}` only) decodes unchanged — see
/// `MultiCoverageTests.oldTwoFieldJSONDecodesWithNewFieldsNil` for the
/// back-compat proof. Flag-off / pre-v3 clients that re-encode a line (e.g.
/// editing an unrelated field) write these fields back out as `null`, which
/// is itself forward-compatible: a v3 client reading them back still gets
/// `nil`.
///
/// `nonisolated`: pure value data, no UI/actor state — the project defaults
/// declarations to `@MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)
/// and this is constructed directly in tests off the main actor.
nonisolated struct CoverageLine: Codable, Hashable, Identifiable {
    /// Stable per-line identity for SwiftUI `ForEach`/list diffing (the
    /// editor's `ForEach($coverageLines)` used to key off `label`, which
    /// broke on duplicate labels and re-identified the row on every
    /// keystroke). Deliberately excluded from `==`/`hash(into:)` below —
    /// it's identity, not value — so it stays additive: every existing
    /// round-trip comparison (`CoverageLine(label:covered:) ==` a decoded
    /// line) keeps working even though the two now carry different ids.
    var id: UUID = UUID()
    var label: String
    var covered: Bool
    /// When this specific line's coverage began. Anchors its own ring/months
    /// math the same way `PurchaseRecord.purchaseDate` anchors the single-line
    /// v2 ring — independent per line since e.g. an extended-warranty line
    /// starts later than the base warranty line on the same item.
    var startDate: Date? = nil
    /// When this line lapses. `nil` means "no expiry tracked for this line" —
    /// falls back to the plain `covered` flag for active/expired purposes
    /// (see `isActive(now:)`), matching pre-v3 lines exactly.
    var endDate: Date? = nil
    /// "warranty" | "extended" | "insurance" (`CoverageLineKind.rawValue`) —
    /// plain `String?` rather than a non-optional enum so an unrecognized or
    /// future value round-trips through decode/encode instead of failing.
    var kind: String? = nil
    /// Optional scope note, e.g. ["Panel defects"] — shown as free text in
    /// the passport row's sub-line when present. Not editable from the v3
    /// coverage-line editor (V3_BRIEF §2 doesn't call for it); wired through
    /// so a future editor pass or import path can set it.
    var coveredItems: [String]? = nil

    init(
        id: UUID = UUID(),
        label: String,
        covered: Bool,
        startDate: Date? = nil,
        endDate: Date? = nil,
        kind: String? = nil,
        coveredItems: [String]? = nil
    ) {
        self.id = id
        self.label = label
        self.covered = covered
        self.startDate = startDate
        self.endDate = endDate
        self.kind = kind
        self.coveredItems = coveredItems
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, covered, startDate, endDate, kind, coveredItems
    }

    /// Old JSON blobs (persisted before `id` — or, earlier still, before any
    /// of the v3 fields — existed) have no key for whichever fields didn't
    /// exist yet. `id` defaults to a fresh one; the v3 fields default to
    /// `nil`, matching what synthesized `Decodable` would have done for them
    /// automatically (this file only needs a custom `init(from:)` at all
    /// because of `id`'s non-optional-with-default shape).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try container.decode(String.self, forKey: .label)
        covered = try container.decode(Bool.self, forKey: .covered)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        coveredItems = try container.decodeIfPresent([String].self, forKey: .coveredItems)
    }

    /// Value equality over everything except `id` (identity, not value —
    /// see the property's doc comment).
    static func == (lhs: CoverageLine, rhs: CoverageLine) -> Bool {
        lhs.label == rhs.label
            && lhs.covered == rhs.covered
            && lhs.startDate == rhs.startDate
            && lhs.endDate == rhs.endDate
            && lhs.kind == rhs.kind
            && lhs.coveredItems == rhs.coveredItems
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(covered)
        hasher.combine(startDate)
        hasher.combine(endDate)
        hasher.combine(kind)
        hasher.combine(coveredItems)
    }
}

/// Display metadata for `CoverageLine.kind`'s known values. Kept separate
/// from the raw `String?` storage (see `CoverageLine.kind` doc) so unrecognized
/// values still round-trip.
nonisolated enum CoverageLineKind: String, CaseIterable, Identifiable, Hashable {
    case warranty
    case extended
    case insurance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .warranty: "Warranty"
        case .extended: "Extended warranty"
        case .insurance: "Insurance"
        }
    }
}

// `nonisolated` repeated per-member (not on the `extension` line): the base
// type's own `nonisolated struct CoverageLine` doesn't extend to members
// declared in a separate `extension` block — those default back to
// `@MainActor` under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` unless
// marked, same as e.g. `PurchaseRecord.returnWindowStatus`. These two are
// pure value computations called from `MultiCoverageTests` off the main
// actor, so they need it explicitly.
extension CoverageLine {
    /// Convenience typed accessor over the raw `kind` string — `nil` for both
    /// "no kind set" and "kind set to something this build doesn't recognize"
    /// (the raw string itself is preserved either way, only this computed
    /// view collapses the two).
    nonisolated var kindEnum: CoverageLineKind? {
        get { kind.flatMap(CoverageLineKind.init(rawValue:)) }
        set { kind = newValue?.rawValue }
    }

    /// Whether this line is currently active (V3_BRIEF §2 semantics):
    /// `endDate != nil ? endDate >= today : covered`. A line with a tracked
    /// expiry is active purely by date, regardless of what `covered` says;
    /// a line with no expiry (every pre-v3 line, and any v3 line the user
    /// never dated) falls back to the plain `covered` flag exactly like v2.
    nonisolated func isActive(now: Date = .now) -> Bool {
        guard let endDate else { return covered }
        return endDate >= Calendar.current.startOfDay(for: now)
    }
}
