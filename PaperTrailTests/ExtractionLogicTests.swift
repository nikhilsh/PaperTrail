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

    @Test func picksGrandTotalOverSavingsRow() {
        // A "Total Savings"/"Total Discount" line shares the "total" rank and, by
        // appearing first, used to win — saving 200.00 was reported as the total.
        let table = OCRTable(rows: [
            ["Subtotal", "1,499.00"],
            ["Total Savings", "200.00"],
            ["Total", "1,299.00"],
        ])
        #expect(DocumentStructureOCRService.detectTotal(in: [table]) == 1299.00)
    }

    @Test func picksTotalAmountNotLargerCellOnSameRow() {
        // When the total row also carries a larger figure (RRP / "you saved"), the
        // rightmost amount is the total — `.max()` used to grab the bigger one.
        let table = OCRTable(rows: [
            ["Total", "1,500.00", "1,299.00"],
        ])
        #expect(DocumentStructureOCRService.detectTotal(in: [table]) == 1299.00)
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

    @Test func groundingRejectsSmallRoundHallucinationsAndOddValues() {
        let text = "BUILT IN OVEN 919.00\nINDUCTION HOB 759.00\nTotal SGD 1,837.00"
        // A hallucinated small round amount must not "ground" just because its
        // digits appear inside a larger figure ("9" lives in "919", "1837").
        #expect(!ExtractionPipeline.amountAppears(9.00, in: text))
        #expect(!ExtractionPipeline.amountAppears(8.00, in: text))
        // A genuine standalone integer-form amount is still accepted.
        #expect(ExtractionPipeline.amountAppears(919.00, in: "INDUCTION HOB 919"))
        // Odd/garbled model amounts must return false, never trap on Int(_:).
        #expect(!ExtractionPipeline.amountAppears(.nan, in: text))
        #expect(!ExtractionPipeline.amountAppears(.infinity, in: text))
        #expect(!ExtractionPipeline.amountAppears(-.infinity, in: text))
        #expect(!ExtractionPipeline.amountAppears(1e19, in: text))   // beyond Int range
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

    // MARK: - Transcript text price overlay (per-item auto-fill catch-all)

    @Test func overlaysTextPricesForBlankItems() {
        // Real Gain City layout: names + prices on the same transcript line.
        let text = """
        BRANDT GAS HOB TI1100B 859.00
        BUILT IN OVEN BXP6355X 919.00
        BRANDT INDUCTION HOB TI1018B 759.00
        REBATE -700.00
        Total SGD 1,837.00
        """
        let items = [
            LineItem(name: "Brandt Gas Hob", amount: nil, kind: .product),
            LineItem(name: "Built In Oven", amount: nil, kind: .product),
            LineItem(name: "Brandt Induction Hob", amount: nil, kind: .product),
        ]
        let filled = ExtractionPipeline.overlayTextPrices(items, text: text)
        #expect(filled.map(\.amount) == [859.00, 919.00, 759.00])
    }

    @Test func textOverlayIgnoresIntegerCodesAndSummaryRows() {
        // Model number 4502 must not be read as a price; only the 2-decimal token is.
        #expect(ExtractionPipeline.priceOnLine("LG 2 DOOR FRIDGE GT-F4502PF 1299.00") == 1299.00)
        #expect(ExtractionPipeline.priceOnLine("LG FRIDGE MODEL GT-F4502PF") == nil)
        #expect(ExtractionPipeline.isMoneyToken("859.00"))
        #expect(ExtractionPipeline.isMoneyToken("1,299.00"))
        #expect(ExtractionPipeline.isMoneyToken("$49.90"))
        #expect(!ExtractionPipeline.isMoneyToken("4502"))
        #expect(!ExtractionPipeline.isMoneyToken("GT-F4502PF"))
        #expect(!ExtractionPipeline.isMoneyToken("60CM"))
    }

    @Test func textOverlayKeepsExistingAmountsAndUnmatchedBlanks() {
        let text = "BRANDT GAS HOB 859.00\nTotal 859.00"
        let items = [
            LineItem(name: "Brandt Gas Hob", amount: 859.00, kind: .product),   // already filled → keep
            LineItem(name: "Dishwasher Quartz", amount: nil, kind: .product),   // not in text → stays blank
        ]
        let filled = ExtractionPipeline.overlayTextPrices(items, text: text)
        #expect(filled[0].amount == 859.00)
        #expect(filled[1].amount == nil)
    }

    // MARK: - Line-item sanity filter (column-major OCR noise)

    @Test func plausibleProductKeepsRealDevices() {
        // Real products from the Gain City sales order — must survive.
        #expect(ExtractionPipeline.isPlausibleProduct("LG WASHER/DRYER - 10/6KG"))
        #expect(ExtractionPipeline.isPlausibleProduct("LG 2 DOOR FRIDGE"))
        #expect(ExtractionPipeline.isPlausibleProduct("RHEEM STORAGE HEATER 20L"))
        #expect(ExtractionPipeline.isPlausibleProduct("EW-PREMIUM-WASHER FRONT/COMBO"))
        // Lowercase product names with a trailing number are kept (not a bare code).
        #expect(ExtractionPipeline.isPlausibleProduct("iPhone15 Pro"))
    }

    @Test func plausibleProductRejectsOCRNoise() {
        // Bare model numbers / SKU codes.
        #expect(!ExtractionPipeline.isPlausibleProduct("FV1410H3BA"))
        #expect(!ExtractionPipeline.isPlausibleProduct("GT-F4604EP"))
        #expect(!ExtractionPipeline.isPlausibleProduct("XS-20-SLIM"))
        // Warranty / promo SKU lines.
        #expect(!ExtractionPipeline.isPlausibleProduct("NPW~WF (2+3 YRS)"))
        #expect(!ExtractionPipeline.isPlausibleProduct("NPW~FG (2+3 YRS)"))
        // Free-of-charge gifts and redemption promos.
        #expect(!ExtractionPipeline.isPlausibleProduct("FOC 3L BABIENCE FIRST CLEAN DETERGENT"))
        #expect(!ExtractionPipeline.isPlausibleProduct("FOC $50 GROCERY VOC FROM 1/1 - 30/6."))
        // Section separators and metadata / summary labels.
        #expect(!ExtractionPipeline.isPlausibleProduct("*** GROUP 2***"))
        #expect(!ExtractionPipeline.isPlausibleProduct("Manual Order No."))
        #expect(!ExtractionPipeline.isPlausibleProduct("Discount"))
        #expect(!ExtractionPipeline.isPlausibleProduct("Total amount due"))
        #expect(!ExtractionPipeline.isPlausibleProduct("INSTANT CASH REBATE"))
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

    // MARK: - Embedding similarity (CategoryClassifier caching refactor)

    @Test func cosineSimilarityMatchesSimilarityScale() {
        // The category classifier now embeds the query ONCE and compares against
        // cached exemplar vectors via cosineSimilarity, instead of re-embedding
        // both strings per exemplar. This locks the scale so ranking is unchanged:
        // identical → 1, orthogonal → 0.5, opposite → 0 (mirrors `similarity`'s
        // `1 - distance/2` mapping). Pure math — no embedding asset needed in CI.
        let m = SemanticMatcher.shared
        #expect(m.cosineSimilarity([1, 0, 0], [1, 0, 0]) == 1.0)        // identical
        #expect(m.cosineSimilarity([1, 0], [0, 1]) == 0.5)             // orthogonal
        #expect(m.cosineSimilarity([1, 0], [-1, 0]) == 0.0)           // opposite
        #expect(m.cosineSimilarity([], []) == nil)                    // undefined
        #expect(m.cosineSimilarity([1, 0], [1, 0, 0]) == nil)         // length mismatch
        #expect(m.cosineSimilarity([0, 0], [1, 1]) == nil)           // zero vector
    }

    // MARK: - Primary item rebind (multi-item edit preservation)

    @Test func reboundFillsUntouchedAndEmptyFields() {
        let prev = LineItem(name: "Old Item", amount: 100.0, kind: .product)
        let next = LineItem(name: "New Item", amount: 200.0, kind: .product)
        // Fields still equal to the previous primary (untouched) → adopt new primary.
        #expect(PrimaryItemBinding.rebound(previousPrimary: prev, newPrimary: next,
            current: .init(productName: "Old Item", amountText: "100.00"))
            == .init(productName: "New Item", amountText: "200.00"))
        // Empty fields → filled from the new primary.
        #expect(PrimaryItemBinding.rebound(previousPrimary: prev, newPrimary: next,
            current: .init(productName: "", amountText: ""))
            == .init(productName: "New Item", amountText: "200.00"))
    }

    @Test func reboundPreservesHandEditedFields() {
        let prev = LineItem(name: "Old Item", amount: 100.0, kind: .product)
        let next = LineItem(name: "New Item", amount: 200.0, kind: .product)
        // Both fields hand-edited → both preserved across the selection change.
        #expect(PrimaryItemBinding.rebound(previousPrimary: prev, newPrimary: next,
            current: .init(productName: "My Edit", amountText: "149.99"))
            == .init(productName: "My Edit", amountText: "149.99"))
        // Mixed: name edited, amount still the previous primary's → only amount updates.
        #expect(PrimaryItemBinding.rebound(previousPrimary: prev, newPrimary: next,
            current: .init(productName: "My Edit", amountText: "100.00"))
            == .init(productName: "My Edit", amountText: "200.00"))
    }

    @Test func reboundNoopWhenPrimaryUnchangedOrCleared() {
        let prev = LineItem(name: "Old Item", amount: 100.0, kind: .product)
        let edited = PrimaryItemBinding.Fields(productName: "My Edit", amountText: "149.99")
        // Same primary id → never touches the fields.
        #expect(PrimaryItemBinding.rebound(previousPrimary: prev, newPrimary: prev, current: edited) == edited)
        // All record-worthy items deselected (no new primary) → fields untouched.
        #expect(PrimaryItemBinding.rebound(previousPrimary: prev, newPrimary: nil, current: edited) == edited)
    }

    // MARK: - Claim packet gating (no proof → no offer)

    @Test func claimPacketOnlyOfferedWithProof() {
        #expect(!ClaimPacketAvailability.isOffered(attachmentCount: 0))
        #expect(ClaimPacketAvailability.isOffered(attachmentCount: 1))
        #expect(ClaimPacketAvailability.isOffered(attachmentCount: 5))
    }
}
