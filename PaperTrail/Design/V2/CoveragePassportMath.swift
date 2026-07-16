import Foundation

// MARK: - CoveragePassportMath (docs/design-v2/V2_BRIEF.md §2, W2)
//
// Pure, nonisolated helpers for the Coverage Passport's ring: which unit to
// display (months normally, days once there's under 2 months left — "9 mo
// left" stops being a meaningful reading in the final weeks) and the
// total/remaining span in that unit. No SwiftUI, no `Date.now` default
// baked in past the call site, so this is trivially testable.

/// Display unit for the Coverage Ring's center number. `nonisolated` — like
/// `coverageRingValues` below and `PTMembershipTerm` elsewhere in this folder
/// — because the project defaults declarations to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) and pure value types with no
/// UI/actor state have no business being actor-isolated; tests call these
/// off the main actor.
nonisolated enum CoverageRingUnit: Equatable {
    case months
    case days

    /// Short mono suffix shown after the number, e.g. "9 mo" / "18 d".
    var suffix: String {
        switch self {
        case .months: "mo"
        case .days: "d"
        }
    }
}

/// The Coverage Ring's total span and how much of it remains, expressed in
/// whichever unit reads best.
nonisolated struct CoverageRingValues: Equatable {
    let total: Int
    let remaining: Int
    let unit: CoverageRingUnit
}

/// Computes the Coverage Ring's total/remaining span for a warranty window.
///
/// `purchaseDate` anchors the "total" span (elapsed vs. total warranty, per
/// the brief). When it's missing — a warranty expiry with no purchase date on
/// file — there's no way to know how long the original window was, so this
/// falls back to a full ring (`total == remaining`) rather than guessing.
nonisolated func coverageRingValues(purchaseDate: Date?, expiryDate: Date, now: Date = .now) -> CoverageRingValues {
    let calendar = Calendar.current
    let remainingMonths = max(0, calendar.dateComponents([.month], from: now, to: expiryDate).month ?? 0)

    if remainingMonths < 2 {
        let remainingDays = max(0, calendar.dateComponents([.day], from: now, to: expiryDate).day ?? 0)
        let totalDays: Int
        if let purchaseDate {
            totalDays = max(1, calendar.dateComponents([.day], from: purchaseDate, to: expiryDate).day ?? 1)
        } else {
            totalDays = max(1, remainingDays)
        }
        return CoverageRingValues(total: totalDays, remaining: remainingDays, unit: .days)
    }

    let totalMonths: Int
    if let purchaseDate {
        totalMonths = max(1, calendar.dateComponents([.month], from: purchaseDate, to: expiryDate).month ?? 1)
    } else {
        totalMonths = max(1, remainingMonths)
    }
    return CoverageRingValues(total: totalMonths, remaining: remainingMonths, unit: .months)
}
