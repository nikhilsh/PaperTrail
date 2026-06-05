import Testing
import Foundation
@testable import PaperTrail

/// Tests for the anchored column-major price fill — the follow-up to the
/// build-14 diagnosis (iOS 26's recognizer serializes some receipt tables
/// column-by-column, so descriptions and prices never share a line).
struct ColumnPriceFillTests {

    /// Structurally faithful to the diagnosed sales-order transcript: item
    /// codes column, then descriptions (with model/promo noise), then qty,
    /// then the LCN code alternating 1:1 with the unit-price column, then the
    /// line-total column and summary block.
    private let columnMajorTranscript = """
    MEGA ELECTRIC PTE LTD
    RE-PRINT SALES ORDER
    No
    Description / Model
    T0176905
    T0195749
    T0178370
    LG WASHER/DRYER - 10/6KG
    FV1410H3BA
    LG 2 DOOR FRIDGE
    GT-F4604EP
    RHEEM STORAGE HEATER 20L
    XS-20-SLIM
    *** GROUP 2***
    BTO - INSTANT CASH REBAT
    EW-PREMIUM-REFRIGERATION
    NO DISPOSAL - CE
    Qty UOM
    1 UNIT
    1 UNIT
    1 UNIT
    29 UNIT
    1 UNIT
    1 UNIT
    1 UNIT
    LCN
    Unit Price
    02SKMW
    1,479.00
    02SKMW
    1,269.00
    02SKMW
    318.00
    02SKMW
    - 20.00
    02SKMW
    309.00
    02SKMW
    319.00
    02SKMW
    Total amount due
    GST Amount @ 9%
    Disc.
    Amt.
    Total
    1,479.00
    1,269.00
    318.00
    - 580.00
    309.00
    319.00
    3,114.00
    257.12
    2,856.88
    """

    private func items(washerAmount: Double? = 1479.00) -> [LineItem] {
        [
            LineItem(name: "LG WASHER/DRYER - 10/6KG", amount: washerAmount),
            LineItem(name: "LG 2 DOOR FRIDGE"),
            LineItem(name: "RHEEM STORAGE HEATER 20L"),
        ]
    }

    @Test func fillsColumnMajorPrices() {
        let filled = ExtractionPipeline.overlayAnchoredColumnPrices(items(), text: columnMajorTranscript)
        #expect(filled[0].amount == 1479.00) // pre-existing amount untouched
        #expect(filled[1].amount == 1269.00) // fridge — row 2's unit price
        #expect(filled[2].amount == 318.00)  // heater — row 3's unit price
    }

    @Test func detectsAnchoredColumn() {
        let lines = columnMajorTranscript.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let column = ExtractionPipeline.anchoredPriceColumn(in: lines)
        #expect(column != nil)
        #expect(column?.rowPrices.count == 7)
        #expect(column?.rowPrices[0] == 1479.00)
        #expect(column?.rowPrices[3] == -20.00)  // rebate row — negative, never filled
        #expect(column?.rowPrices[6] == nil)     // disposal row has no price
    }

    @Test func noFillWhenItemsOutOfTranscriptOrder() {
        let shuffled = [items()[1], items()[0], items()[2]]
        let result = ExtractionPipeline.overlayAnchoredColumnPrices(shuffled, text: columnMajorTranscript)
        #expect(result.compactMap(\.amount) == [1479.00]) // only the pre-set one
    }

    @Test func noFillOnRowMajorReceipt() {
        let rowMajor = """
        ACME STORE
        LG WASHER/DRYER - 10/6KG 1,479.00
        LG 2 DOOR FRIDGE 1,269.00
        RHEEM STORAGE HEATER 20L 318.00
        TOTAL 3,066.00
        """
        let result = ExtractionPipeline.overlayAnchoredColumnPrices(items(washerAmount: nil), text: rowMajor)
        #expect(result.allSatisfy { $0.amount == nil }) // no anchor column → untouched
    }

    @Test func noFillWhenMoreItemsThanRows() {
        var many = items()
        for i in 0..<5 { many.append(LineItem(name: "EXTRA ITEM NUMBER \(i) ALPHA")) }
        let result = ExtractionPipeline.overlayAnchoredColumnPrices(many, text: columnMajorTranscript)
        #expect(result.filter { $0.amount != nil }.count == 1)
    }

    @Test func lineMoneyValueParsing() {
        #expect(ExtractionPipeline.lineMoneyValue("1,479.00") == 1479.00)
        #expect(ExtractionPipeline.lineMoneyValue("- 20.00") == -20.00)
        #expect(ExtractionPipeline.lineMoneyValue("02SKMW") == nil)   // letters
        #expect(ExtractionPipeline.lineMoneyValue("1 UNIT") == nil)   // letters
        #expect(ExtractionPipeline.lineMoneyValue("68991212") == nil) // no decimals
        #expect(ExtractionPipeline.lineMoneyValue("17/8/2025") == nil)
    }
}
