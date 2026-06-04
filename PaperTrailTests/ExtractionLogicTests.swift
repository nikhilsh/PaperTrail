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
