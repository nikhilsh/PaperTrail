import Foundation

/// The gold member card's last-known display parameters, persisted so the
/// Settings hero can render the gold card on its FIRST frame.
///
/// Without this, every Settings visit rebuilt `membershipInfo` from a nil
/// `@State` by iterating StoreKit's `Transaction.currentEntitlements` —
/// asynchronous and slow enough that the cream library card always painted
/// first and visibly "flashed" into gold (device feedback, build 54).
///
/// Stale-while-revalidate: the live StoreKit load still runs on every visit
/// and overwrites/clears this snapshot, so a renewal date change or a lapse
/// is at most one visit behind — and `hasPlus` (checked separately, already
/// persisted by `PlusEntitlements`) gates the card, so a lapsed member never
/// sees a gold card just because a stale snapshot exists.
nonisolated struct PlusMembershipCardSnapshot: Codable, Equatable {
    var memberNumber: String
    var termKind: String
    var renewsOn: String
    var dayText: String
    var notificationsAuthorized: Bool

    private static let key = "plus.membershipCard.v1"

    init(memberNumber: String, term: PTMembershipTerm, notificationsAuthorized: Bool) {
        self.memberNumber = memberNumber
        self.notificationsAuthorized = notificationsAuthorized
        switch term {
        case .annual(let renewsOn):
            termKind = "annual"; self.renewsOn = renewsOn; dayText = ""
        case .monthly(let renewsOn, let dayText):
            termKind = "monthly"; self.renewsOn = renewsOn; self.dayText = dayText
        case .trial(let billsOn):
            termKind = "trial"; renewsOn = billsOn; dayText = ""
        case .lifetime:
            termKind = "lifetime"; renewsOn = ""; dayText = ""
        }
    }

    /// nil only for an unrecognized `termKind` (e.g. a future build wrote a
    /// kind this build doesn't know) — callers fall back to the async load.
    var term: PTMembershipTerm? {
        switch termKind {
        case "annual": .annual(renewsOn: renewsOn)
        case "monthly": .monthly(renewsOn: renewsOn, dayText: dayText)
        case "trial": .trial(billsOn: renewsOn)
        case "lifetime": .lifetime
        default: nil
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
