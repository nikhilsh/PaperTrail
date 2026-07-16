import Foundation

/// Which aggregation surfaces should ignore a "passed on" record.
///
/// Pure predicate, no I/O — `LibraryView` (attention count, sort/room
/// lists), `WarrantyView` (needs-attention/resting-easy/digest), and
/// `WidgetSnapshotWriter`/`DigestScheduler` (coverage counts, dominant-
/// currency total, digest inputs, widget candidates) all filter their
/// `[PurchaseRecord]` through this before computing any count/value.
enum PassItOnAggregation {
    /// `true` when `passedOnDate` should be treated as "sold, don't count
    /// this" — only when the `passItOn` flag is actually on. Flag-off must
    /// ignore `passedOnDate` entirely (data written by a flagged feature is
    /// ignored, not destroyed, once the flag flips off — see
    /// V3_BRIEF.md acceptance criteria), so a flag-off client's totals
    /// exactly match pre-v3 behavior even for a record some other
    /// flag-on client marked passed-on.
    nonisolated static func isExcludedFromAggregates(passedOnDate: Date?, flagOn: Bool) -> Bool {
        flagOn && passedOnDate != nil
    }
}

/// Page selection + live page count for the "Pass it on" buyer-packet
/// builder (docs/design-v3/V3_BRIEF.md §7, V3-1 mock).
enum PassItOnPacket {
    /// Which checklist rows the user has toggled on. Defaults match the
    /// V3-1 mock: proof/warranty/service on, manual/price off.
    struct Selection: Equatable, Sendable {
        var includeProofOfPurchase: Bool = true
        var includeRemainingWarranty: Bool = true
        var includeServiceHistory: Bool = true
        var includeManual: Bool = false
        var showPricePaid: Bool = false
    }

    /// What's actually on file for this record — a checklist row only
    /// contributes a page when it's BOTH selected AND available (e.g.
    /// "Remaining warranty" is meaningless with no `warrantyExpiryDate`).
    struct Availability: Equatable, Sendable {
        var hasProofOfPurchase: Bool
        var hasRemainingWarranty: Bool
        var hasServiceHistory: Bool
        var hasManual: Bool
        /// The manual's own page count, when `hasManual` — the manual is
        /// embedded as a full PDF, not summarized onto one page, so it can
        /// contribute more than one page to the packet.
        var manualPageCount: Int = 1
    }

    /// Live content-page count for the "Buyer packet · N pages" row —
    /// mirrors the V3-1 mock's "3 pages" for proof + warranty + service
    /// checked. Deliberately excludes the cover page (the mock's count is a
    /// content count, not a physical-PDF-page count); `PassItOnPacketPDF`
    /// always renders one extra cover page on top of this.
    nonisolated static func pageCount(selection: Selection, availability: Availability) -> Int {
        var count = 0
        if selection.includeProofOfPurchase && availability.hasProofOfPurchase { count += 1 }
        if selection.includeRemainingWarranty && availability.hasRemainingWarranty { count += 1 }
        if selection.includeServiceHistory && availability.hasServiceHistory { count += 1 }
        if selection.includeManual && availability.hasManual {
            count += max(availability.manualPageCount, 1)
        }
        return count
    }
}
