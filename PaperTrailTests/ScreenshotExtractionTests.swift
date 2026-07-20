import Testing
import Foundation
import CoreGraphics
@testable import PaperTrail

/// Defenses against screenshot inputs (the "Nike / 11:45 / MYR" record):
/// status-bar chrome must not become field values, "rm" inside ordinary
/// words must not flip the currency to MYR, and the document-region crop
/// decision must only fire when the page is a minority of the frame.
struct ScreenshotExtractionTests {

    // MARK: - Clock times

    @Test func statusBarClockIsRecognized() {
        #expect(HeuristicFieldExtractor.looksLikeClockTime("11:45"))
        #expect(HeuristicFieldExtractor.looksLikeClockTime("9:41 AM"))
        #expect(HeuristicFieldExtractor.looksLikeClockTime("9:41PM"))
        #expect(!HeuristicFieldExtractor.looksLikeClockTime("Gain City"))
        #expect(!HeuristicFieldExtractor.looksLikeClockTime("11:45 checkout lane"))
        #expect(!HeuristicFieldExtractor.looksLikeClockTime("23/03/2026"))
    }

    @Test func clockLineDoesNotConsumeTheMerchantPick() {
        // The clock is the first OCR line of a screenshot; the real merchant
        // sits below it and must still be found.
        let text = """
        11:45
        Gain City
        Receipt
        Subtotal 129.00
        """
        let result = HeuristicFieldExtractor().extract(from: text)
        #expect(result.merchantName.value == "Gain City")
    }

    @Test func clockTimeNeverPassesMerchantValidation() {
        let text = """
        11:45
        .
        ..
        """
        let result = HeuristicFieldExtractor().extract(from: text)
        #expect(result.merchantName.value == nil)
    }

    // MARK: - MYR currency

    @Test func rmInsideOrdinaryWordsIsNotMYR() {
        let text = """
        Spray arm top
        Incoterms DAP Ship-to address
        Remarks
        Total Net 24.99
        """
        let result = HeuristicFieldExtractor().extract(from: text)
        #expect(result.currency.value == nil)
    }

    @Test func realRinggitAmountsStillDetectAsMYR() {
        let withSpace = HeuristicFieldExtractor().extract(from: "Total RM 129.00")
        #expect(withSpace.currency.value == "MYR")
        let noSpace = HeuristicFieldExtractor().extract(from: "Total RM129.00")
        #expect(noSpace.currency.value == "MYR")
        let iso = HeuristicFieldExtractor().extract(from: "Currency MYR Total 129.00")
        #expect(iso.currency.value == "MYR")
    }

    @Test func usdStillWinsOverStrayRM() {
        let result = HeuristicFieldExtractor().extract(from: "Currency USD\nSpray arm top RM 1")
        #expect(result.currency.value == "USD")
    }

    // MARK: - Column-major totals (Bosch invoice)

    @Test func columnMajorTotalsBlockYieldsTheInvoiceAmount() {
        // The Bosch invoice OCR serializes the totals section labels-first,
        // numbers-after; the true invoice amount sits 8 lines below the
        // "Total Amount" label. A 5-line window used to return the freight
        // charge (27.00) instead.
        let text = """
        Total Amount Netpricel
        Sales tax
        Invoice Amount
        Net Price
        24.99
        27.00
        51.99
        2.34
        54.33
        """
        let result = HeuristicFieldExtractor().extract(from: text)
        #expect(result.amount.value == 54.33)
    }

    // MARK: - Document-region crop decision

    @Test func smallDocumentRegionProducesACropWithMargin() throws {
        // Invoice page occupying the middle ~30% of a screenshot frame.
        let box = CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.4)
        let rect = DocumentRegionCropper.cropRect(boundingBox: box, pixelWidth: 1000, pixelHeight: 2000)
        let unwrapped = try #require(rect)
        // Margin expands beyond the raw box on every side (y flips axes).
        #expect(unwrapped.minX < 0.1 * 1000)
        #expect(unwrapped.maxX > 0.9 * 1000)
        #expect(unwrapped.minY < (1 - 0.7) * 2000)
        #expect(unwrapped.maxY > (1 - 0.3) * 2000)
        // And stays inside the frame.
        #expect(unwrapped.minX >= 0 && unwrapped.minY >= 0)
        #expect(unwrapped.maxX <= 1000 && unwrapped.maxY <= 2000)
    }

    @Test func nearFullFrameDetectionDoesNotCrop() {
        // A camera scan detects as ~the whole frame — no crop.
        let box = CGRect(x: 0.02, y: 0.02, width: 0.96, height: 0.96)
        #expect(DocumentRegionCropper.cropRect(boundingBox: box, pixelWidth: 1000, pixelHeight: 2000) == nil)
    }

    @Test func degenerateDetectionDoesNotCrop() {
        let empty = CGRect(x: 0.5, y: 0.5, width: 0, height: 0.3)
        #expect(DocumentRegionCropper.cropRect(boundingBox: empty, pixelWidth: 1000, pixelHeight: 2000) == nil)
    }
}
