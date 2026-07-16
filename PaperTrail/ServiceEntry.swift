import Foundation

/// A single logged repair/service event on the `serviceLedger` timeline
/// (docs/design-v3/V3_BRIEF.md §4) — e.g. "Panel flicker — mainboard
/// replaced" under warranty, or "Firmware 1408.4 installed" self-serviced.
///
/// Backed by `PurchaseRecord.serviceEntriesData` (small JSON blob, same
/// additive-optional pattern as `CoverageLine`/`coverageLinesData`) via the
/// `serviceEntries` computed property on `PurchaseRecord` — never read/write
/// the raw blob directly.
///
/// `nonisolated`: pure value data, no UI/actor state — same reasoning as
/// `CoverageLine` (the project defaults declarations to `@MainActor` via
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and this is constructed
/// directly in tests off the main actor).
nonisolated struct ServiceEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    /// "self" | "authorized" | "shop" (`ServiceActorKind.rawValue`) — plain
    /// `String` rather than a non-optional enum so an unrecognized or future
    /// value round-trips through decode/encode instead of failing, matching
    /// `CoverageLine.kind`'s reasoning.
    var actor: String
    var title: String
    var cost: Decimal? = nil
    var jobRef: String? = nil
    /// Links to existing `Attachment`s (e.g. photos of the repair) by id —
    /// modeled now so the schema doesn't need another migration once the
    /// entry form grows a photo picker, but nothing in this wave writes to
    /// it (the log-a-repair sheet only collects date/actor/title/cost/job
    /// ref per V3_BRIEF §4). `nil` and `[]` both mean "no photos".
    var attachmentIDs: [UUID]? = nil

    init(
        id: UUID = UUID(),
        date: Date,
        actor: String,
        title: String,
        cost: Decimal? = nil,
        jobRef: String? = nil,
        attachmentIDs: [UUID]? = nil
    ) {
        self.id = id
        self.date = date
        self.actor = actor
        self.title = title
        self.cost = cost
        self.jobRef = jobRef
        self.attachmentIDs = attachmentIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, actor, title, cost, jobRef, attachmentIDs
    }

    /// Defaults `id` for any future pre-`id` blob shape the same way
    /// `CoverageLine.init(from:)` does, even though every `ServiceEntry`
    /// ever persisted by this app already has one — cheap insurance, no
    /// downside, and keeps the two additive-schema types symmetric.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        actor = try container.decode(String.self, forKey: .actor)
        title = try container.decode(String.self, forKey: .title)
        cost = try container.decodeIfPresent(Decimal.self, forKey: .cost)
        jobRef = try container.decodeIfPresent(String.self, forKey: .jobRef)
        attachmentIDs = try container.decodeIfPresent([UUID].self, forKey: .attachmentIDs)
    }
}

/// Display metadata for `ServiceEntry.actor`'s known values. Kept separate
/// from the raw `String` storage (see `ServiceEntry.actor` doc) so an
/// unrecognized value still round-trips.
nonisolated enum ServiceActorKind: String, CaseIterable, Identifiable, Hashable {
    case selfServiced = "self"
    case authorized
    case shop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .selfServiced: "Self"
        case .authorized: "Authorized"
        case .shop: "Shop"
        }
    }
}

extension ServiceEntry {
    /// Convenience typed accessor over the raw `actor` string — falls back
    /// to `.selfServiced` for display purposes when the raw value is
    /// unrecognized, but never mutates the underlying string just by reading it.
    nonisolated var actorKind: ServiceActorKind? {
        get { ServiceActorKind(rawValue: actor) }
        set { actor = newValue?.rawValue ?? actor }
    }
}

extension Array where Element == ServiceEntry {
    /// Ledger sort order (V3_BRIEF §4 timeline): newest first. Stable for
    /// equal dates by falling back to `id` so `ForEach` diffing/tests get a
    /// deterministic order rather than whatever `sorted` internally picks.
    nonisolated var sortedByDateDescending: [ServiceEntry] {
        sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }
}
