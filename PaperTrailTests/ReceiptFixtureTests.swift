//
//  ReceiptFixtureTests.swift
//  PaperTrailTests
//
//  Golden fixtures from REAL receipts: ground-truth values used to regression-test
//  the deterministic extraction logic. Foundation Models / Vision / embeddings
//  can't run in CI (they need Apple Intelligence on a device), so this harness
//  covers the pure, device-independent paths — date parsing, amount grounding
//  (anti-hallucination), UEN keying, and structured-table reconstruction.
//
//  To extend the eval set: transcribe a receipt's representative OCR text and its
//  known-correct fields into a `Fixture`, then add it to `allFixtures`. The
//  production accuracy signal is the per-field correction rate emitted by
//  `ExtractionMetrics` (see the research doc §7); these fixtures are the
//  regression half of that eval.
//

import Testing
import Foundation
@testable import PaperTrail

struct ReceiptFixtureTests {

    struct Fixture {
        let name: String
        /// Representative OCR text (as Vision would flatten it).
        let ocrText: String
        /// The purchase date exactly as printed, and its correct (y, m, d).
        let dateString: String
        let expectedYMD: (Int, Int, Int)
        /// Merchant tax/registration ID as printed, and its normalized key.
        let uenString: String
        let normalizedUEN: String
        /// Grand total and the genuine per-item line totals.
        let total: Double
        let lineItems: [(name: String, amount: Double)]
        /// Plausible-looking numbers that are NOT on the receipt (hallucinations).
        let hallucinatedAmounts: [Double]
        /// The receipt's line-item table, as the structured recognizer would yield.
        let table: OCRTable
    }

    /// Real receipt — Gain City tax invoice for BRANDT kitchen appliances.
    /// (The one where the model hallucinated 499.90 / 2599.90 / 249.90.)
    static let gainCity = Fixture(
        name: "Gain City BRANDT",
        ocrText: """
        GAIN CITY BEST-ELECTRIC PTE LTD
        MEGA STORE @ SUNGEI KADUT
        GST Reg No M2-0116439-7
        23-Nov-25 10:01:04
        Order Date 01/06/2025
        Tax Invoice Date 15/01/2026
        BRANDT GAS HOB-1 BURNER  859.70  859.00
        BRANDT BUILT IN OVEN - 73L  919.00  919.00
        BRANDT INDUCTION HOB  759.00  759.00
        BTO - INSTANT CASH REBATE  -20.00  -700.00
        Total SGD Incl. GST  1,837.00
        GST Amount @ 9%  151.68
        Total SGD Excl. GST  1,685.32
        """,
        dateString: "23-Nov-25",
        expectedYMD: (2025, 11, 23),
        uenString: "M2-0116439-7",
        normalizedUEN: "M201164397",
        total: 1837.00,
        lineItems: [
            ("BRANDT GAS HOB-1 BURNER", 859.00),
            ("BRANDT BUILT IN OVEN - 73L", 919.00),
            ("BRANDT INDUCTION HOB", 759.00),
        ],
        hallucinatedAmounts: [499.90, 2599.90, 249.90],
        table: OCRTable(rows: [
            ["BRANDT GAS HOB-1 BURNER", "859.70", "859.00"],
            ["BRANDT BUILT IN OVEN - 73L", "919.00", "919.00"],
            ["BRANDT INDUCTION HOB", "759.00", "759.00"],
            ["Total SGD Incl. GST", "1,837.00"],
        ])
    )

    static let allFixtures: [Fixture] = [gainCity]

    // MARK: - Date

    @Test func purchaseDateParsesToGroundTruth() throws {
        for f in Self.allFixtures {
            let date = try #require(FoundationModelExtractionService.parsePurchaseDateString(f.dateString))
            let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
            #expect((c.year!, c.month!, c.day!) == f.expectedYMD)
        }
    }

    // MARK: - UEN keying

    @MainActor
    @Test func uenNormalizesToGroundTruth() {
        for f in Self.allFixtures {
            #expect(MerchantLearningService.normalizeUEN(f.uenString) == f.normalizedUEN)
        }
    }

    // MARK: - Amount grounding (anti-hallucination)

    @Test func realAmountsGroundedHallucinatedRejected() {
        for f in Self.allFixtures {
            #expect(ExtractionPipeline.amountAppears(f.total, in: f.ocrText))
            for item in f.lineItems {
                #expect(ExtractionPipeline.amountAppears(item.amount, in: f.ocrText))
            }
            for bad in f.hallucinatedAmounts {
                #expect(!ExtractionPipeline.amountAppears(bad, in: f.ocrText))
            }
        }
    }

    // MARK: - Structured-table reconstruction

    @Test func tableTotalAndLineItemsReconstruct() {
        let f = Self.gainCity
        #expect(DocumentStructureOCRService.detectTotal(in: [f.table]) == f.total)

        let items = DocumentStructureOCRService.lineItems(from: [f.table])
        #expect(items.count == f.lineItems.count)   // total row excluded
        for expected in f.lineItems {
            #expect(items.contains { $0.name == expected.name && $0.amount == expected.amount })
        }
    }
}
