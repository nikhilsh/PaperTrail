//
//  ExtractionLogicTests.swift
//  PaperTrailTests
//
//  Unit coverage for the deterministic logic introduced by the AI-extraction
//  overhaul. These are pure functions — no Vision / Foundation Models / embeddings
//  (those are asset- and device-dependent and can't run reliably in CI), so the
//  assertions here are stable on the simulator.
//

import Testing
import Foundation
@testable import PaperTrail

struct ExtractionLogicTests {

    // MARK: - Amount parsing (DocumentStructureOCRService.parseAmount)

    @Test func parsesPlainAndCurrencyAmounts() throws {
        #expect(abs(try #require(DocumentStructureOCRService.parseAmount("1299.00")) - 1299.0) < 0.001)
        #expect(abs(try #require(DocumentStructureOCRService.parseAmount("$1,299.00")) - 1299.0) < 0.001)
        #expect(abs(try #require(DocumentStructureOCRService.parseAmount("SGD 49.90")) - 49.90) < 0.001)
        #expect(abs(try #require(DocumentStructureOCRService.parseAmount("1,234,567.89")) - 1_234_567.89) < 0.001)
    }

    @Test func parsesEuropeanDecimalComma() throws {
        // A lone comma with two trailing digits is a decimal separator.
        #expect(abs(try #require(DocumentStructureOCRService.parseAmount("12,50")) - 12.50) < 0.001)
    }

    @Test func rejectsNonAmounts() {
        #expect(DocumentStructureOCRService.parseAmount("Total") == nil)       // no digits
        #expect(DocumentStructureOCRService.parseAmount("") == nil)
        #expect(DocumentStructureOCRService.parseAmount("-5.00") == nil)       // non-positive
        #expect(DocumentStructureOCRService.parseAmount("0.00") == nil)
    }

    // MARK: - Structural total detection (detectTotal)

    @Test func picksTotalOverSubtotalAndTax() {
        let table = OCRTable(rows: [
            ["Subtotal", "100.00"],
            ["GST", "9.00"],
            ["Total", "109.00"],
        ])
        #expect(DocumentStructureOCRService.detectTotal(in: [table]) == 109.00)
    }

    @Test func prefersGrandTotalOverPlainTotal() {
        let table = OCRTable(rows: [
            ["Total", "100.00"],
            ["Grand Total", "129.99"],
        ])
        #expect(DocumentStructureOCRService.detectTotal(in: [table]) == 129.99)
    }

    @Test func returnsNilWhenNoTotalRow() {
        let table = OCRTable(rows: [["Item A", "10.00"], ["Item B", "20.00"]])
        #expect(DocumentStructureOCRService.detectTotal(in: [table]) == nil)
        #expect(DocumentStructureOCRService.detectTotal(in: []) == nil)
    }

    // MARK: - Line-item reconstruction (lineItems)

    @Test func reconstructsLineItemsAndSkipsSummaryRows() {
        let table = OCRTable(rows: [
            ["iPhone 15", "1299.00"],
            ["AppleCare", "199.00"],
            ["Subtotal", "1498.00"],
            ["GST", "104.86"],
            ["Total", "1602.86"],
        ])
        let items = DocumentStructureOCRService.lineItems(from: [table])
        #expect(items.count == 2)
        let names = items.map(\.name)
        #expect(names.contains("iPhone 15"))
        #expect(names.contains("AppleCare"))
        // The AppleCare row resolves its amount to 199.
        let appleCare = items.first { $0.name == "AppleCare" }
        #expect(appleCare?.amount == 199.00)
    }

    // MARK: - OCR vocabulary (OCRVocabulary)

    @Test func customWordsIncludeBrandsAndLearnedMerchants() {
        let words = OCRVocabulary.customWords(learnedMerchants: ["My Local Shop", "X"])
        #expect(words.contains("Samsung"))           // titled from brands
        #expect(words.contains("IKEA"))              // short brand
        #expect(words.contains("My Local Shop"))     // learned merchant merged in
        #expect(!words.contains("X"))                // too short → filtered
        #expect(Set(words).count == words.count)     // de-duplicated
    }

    @Test func defaultCustomWordsAreBrandLexicon() {
        #expect(!OCRVocabulary.customWords().isEmpty)
        #expect(OCRVocabulary.customWords() == OCRVocabulary.brandCustomWords)
    }

    // MARK: - Product name normalization (MerchantLearningService)

    @MainActor
    @Test func normalizesProductNames() {
        #expect(MerchantLearningService.normalizeProductName("AirPods Pro (2nd Gen)") == "airpods pro 2nd gen")
        #expect(MerchantLearningService.normalizeProductName("  Dyson   V15  ") == "dyson v15")
    }

    @MainActor
    @Test func normalizesUENForExactKeying() {
        // Dashes/spaces dropped, uppercased → punctuation variants collapse to one key.
        #expect(MerchantLearningService.normalizeUEN("M2-0116439-7") == "M201164397")
        #expect(MerchantLearningService.normalizeUEN("m2 0116439 7") == "M201164397")
        // Too short to be a reliable identity → nil.
        #expect(MerchantLearningService.normalizeUEN("ab-1") == nil)
    }

    // MARK: - Amount grounding (anti-hallucination)

    @Test func groundsAmountsAgainstOCRText() {
        // Real receipt numbers vs the model's hallucinated ones.
        let text = "BRANDT GAS HOB 859.70 859.00\nBUILT IN OVEN 919.00\nINDUCTION HOB 759.00\nREBATE -700.00\nTotal SGD 1,837.00"
        #expect(ExtractionPipeline.amountAppears(859.00, in: text))
        #expect(ExtractionPipeline.amountAppears(919.0, in: text))
        #expect(ExtractionPipeline.amountAppears(1837.00, in: text))   // comma-grouped, normalized
        #expect(!ExtractionPipeline.amountAppears(2599.90, in: text))  // hallucinated
        #expect(!ExtractionPipeline.amountAppears(499.90, in: text))
        #expect(!ExtractionPipeline.amountAppears(249.90, in: text))
    }

    // MARK: - Table-price overlay (per-item auto-fill)

    @Test func overlaysTablePricesOntoBlankItems() {
        // Text extractor: clean names, prices blanked (model hallucinated → grounded away).
        let items = [
            LineItem(name: "Brandt Gas Hob", amount: nil, kind: .product),
            LineItem(name: "Built In Oven", amount: nil, kind: .product),
            LineItem(name: "Induction Hob", amount: nil, kind: .product),
        ]
        // Table: raw cell names + real prices from the price column.
        let table = [
            LineItem(name: "BRANDT GAS HOB", amount: 859.00),
            LineItem(name: "BUILT IN OVEN", amount: 919.00),
            LineItem(name: "INDUCTION HOB", amount: 759.00),
        ]
        let merged = ExtractionPipeline.overlayTableAmounts(items, from: table)
        #expect(merged.map(\.amount) == [859.00, 919.00, 759.00])
        // Clean names are preserved — only amounts are filled.
        #expect(merged.map(\.name) == ["Brandt Gas Hob", "Built In Oven", "Induction Hob"])
    }

    @Test func overlayKeepsExistingGroundedAmounts() {
        let items = [LineItem(name: "Built In Oven", amount: 919.00, kind: .product)]
        let table = [LineItem(name: "BUILT IN OVEN", amount: 111.11)]
        let merged = ExtractionPipeline.overlayTableAmounts(items, from: table)
        #expect(merged[0].amount == 919.00)  // a real, grounded amount is not overwritten
    }

    @Test func overlayFallsBackToPositionWhenNamesDiffer() {
        // Names don't match at all, but the two lists align 1:1 → positional fill.
        let items = [
            LineItem(name: "Refrigerator", amount: nil, kind: .product),
            LineItem(name: "Microwave", amount: nil, kind: .product),
        ]
        let table = [
            LineItem(name: "ITEM A", amount: 500.00),
            LineItem(name: "ITEM B", amount: 250.00),
        ]
        let merged = ExtractionPipeline.overlayTableAmounts(items, from: table)
        #expect(merged.map(\.amount) == [500.00, 250.00])
    }

    @Test func overlayNoOpWhenTableHasNoPrices() {
        let items = [LineItem(name: "Refrigerator", amount: nil, kind: .product)]
        let table = [LineItem(name: "REFRIGERATOR", amount: nil)]  // name-only column
        let merged = ExtractionPipeline.overlayTableAmounts(items, from: table)
        #expect(merged[0].amount == nil)
    }

    // MARK: - Heuristic line-item metadata rejection

    @Test func rejectsOrderMetadataAsLineItems() {
        let h = HeuristicFieldExtractor()
        // Real garbage seen on a Gain City order confirmation.
        #expect(h.isMetadataLineItem("Order Date"))
        #expect(h.isMetadataLineItem("Delivery Time"))
        #expect(h.isMetadataLineItem("Manual Order No."))
        #expect(h.isMetadataLineItem("SO-B0000142558"))      // order code
        #expect(h.isMetadataLineItem("KENNETH TAN/9295"))    // salesperson/code
        // Real products are NOT rejected.
        #expect(!h.isMetadataLineItem("LG 2 DOOR FRIDGE GT-F4502PF"))
        #expect(!h.isMetadataLineItem("BRANDT INDUCTION HOB"))
    }

    // MARK: - Hint strength: correction count × recency decay (MerchantProfile)

    @Test func hintStrengthRewardsCorrectionsAndPenalizesStaleness() {
        let fresh0 = MerchantProfile(normalizedName: "a", displayName: "A", correctionCount: 0, lastUsedAt: .now)
        let fresh10 = MerchantProfile(normalizedName: "b", displayName: "B", correctionCount: 10, lastUsedAt: .now)
        let stale10 = MerchantProfile(
            normalizedName: "c", displayName: "C", correctionCount: 10,
            lastUsedAt: Date.now.addingTimeInterval(-365 * 86_400)
        )

        // Many recent corrections → near-authoritative; none → weak.
        #expect(fresh10.hintStrength > stale10.hintStrength)
        #expect(stale10.hintStrength > fresh0.hintStrength)
        #expect(fresh10.hintStrength > 0.9)
        #expect(fresh0.hintStrength < 0.4)
        #expect(fresh10.hintStrength <= 1.0)
    }
}
