import Testing
import Foundation
@testable import PaperTrail

/// Pure-logic tests for v3 `passItOn` (docs/design-v3/V3_BRIEF.md §7):
/// `PassItOnPacket.pageCount`'s selection-vs-availability math and
/// `PassItOnAggregation.isExcludedFromAggregates`'s flag-gated predicate.
/// No SwiftData, no PDFKit — everything here is nonisolated value-level
/// logic, mirroring `MultiCoverageTests`/`WidgetSnapshotTests`'s shape.
struct PassItOnPacketTests {

    // MARK: - Page count

    private let fullAvailability = PassItOnPacket.Availability(
        hasProofOfPurchase: true,
        hasRemainingWarranty: true,
        hasServiceHistory: true,
        hasManual: true,
        manualPageCount: 4
    )

    @Test func defaultSelectionCountsProofWarrantyServiceOnly() {
        // Matches the V3-1 mock: proof + warranty + service checked,
        // manual + price unchecked by default → 3 pages.
        let selection = PassItOnPacket.Selection()
        #expect(PassItOnPacket.pageCount(selection: selection, availability: fullAvailability) == 3)
    }

    @Test func togglingManualOnAddsItsFullPageCount() {
        var selection = PassItOnPacket.Selection()
        selection.includeManual = true
        #expect(PassItOnPacket.pageCount(selection: selection, availability: fullAvailability) == 7) // 3 + 4-page manual
    }

    @Test func deselectingEverythingYieldsZeroPages() {
        let selection = PassItOnPacket.Selection(
            includeProofOfPurchase: false,
            includeRemainingWarranty: false,
            includeServiceHistory: false,
            includeManual: false,
            showPricePaid: false
        )
        #expect(PassItOnPacket.pageCount(selection: selection, availability: fullAvailability) == 0)
    }

    @Test func selectedButUnavailableSectionsDoNotCount() {
        // Everything selected, but nothing is actually on file.
        let selection = PassItOnPacket.Selection(
            includeProofOfPurchase: true,
            includeRemainingWarranty: true,
            includeServiceHistory: true,
            includeManual: true,
            showPricePaid: false
        )
        let availability = PassItOnPacket.Availability(
            hasProofOfPurchase: false,
            hasRemainingWarranty: false,
            hasServiceHistory: false,
            hasManual: false
        )
        #expect(PassItOnPacket.pageCount(selection: selection, availability: availability) == 0)
    }

    @Test func showPricePaidDoesNotContributeItsOwnPage() {
        // "Show price paid" toggles content on the existing proof page —
        // it never adds a page of its own.
        var selection = PassItOnPacket.Selection()
        selection.showPricePaid = true
        #expect(PassItOnPacket.pageCount(selection: selection, availability: fullAvailability) == 3)
    }

    @Test func manualWithZeroReportedPagesStillCountsAsOne() {
        var selection = PassItOnPacket.Selection()
        selection.includeManual = true
        var availability = fullAvailability
        availability.manualPageCount = 0
        #expect(PassItOnPacket.pageCount(selection: selection, availability: availability) == 4) // 3 + max(0,1)
    }

    // MARK: - Proof-of-purchase derivation (item 2, HIGH: was a hardcoded
    // `true` stub in the builder before this predicate existed)

    @Test func noAttachmentsMeansNoProofOfPurchase() {
        #expect(!PassItOnPacket.hasProofOfPurchase(attachmentIDs: [], productImageAttachmentID: nil))
    }

    @Test func onlyTheProductPhotoIsNotProofOfPurchase() {
        let photoID = UUID()
        #expect(!PassItOnPacket.hasProofOfPurchase(attachmentIDs: [photoID], productImageAttachmentID: photoID))
    }

    @Test func aNonPhotoAttachmentIsProofOfPurchase() {
        let photoID = UUID()
        let receiptID = UUID()
        #expect(PassItOnPacket.hasProofOfPurchase(attachmentIDs: [photoID, receiptID], productImageAttachmentID: photoID))
    }

    @Test func attachmentsWithNoProductPhotoSetAreStillProofOfPurchase() {
        #expect(PassItOnPacket.hasProofOfPurchase(attachmentIDs: [UUID()], productImageAttachmentID: nil))
    }

    // MARK: - Passed-on exclusion predicate

    @Test func flagOffNeverExcludesRegardlessOfPassedOnDate() {
        #expect(!PassItOnAggregation.isExcludedFromAggregates(passedOnDate: .now, flagOn: false))
    }

    @Test func flagOnExcludesWhenPassedOnDateSet() {
        #expect(PassItOnAggregation.isExcludedFromAggregates(passedOnDate: .now, flagOn: true))
    }

    @Test func flagOnDoesNotExcludeWithNoPassedOnDate() {
        #expect(!PassItOnAggregation.isExcludedFromAggregates(passedOnDate: nil, flagOn: true))
    }
}
