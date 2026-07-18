import Testing
import Foundation
@testable import PaperTrail

/// BUILD_REVIEW W2/W7 — the one remaining-time formatter. These pin the
/// unit thresholds (months ≥ 90d, days 1–89, "today", "expired") and the
/// year rule on absolute dates (> 6 months out).
struct CoverageFormatterTests {

    @Test func unitsFollowTheSpecThresholds() {
        #expect(CoverageFormatter.remaining(days: 321) == "10 mo")
        #expect(CoverageFormatter.remaining(days: 90) == "3 mo")
        #expect(CoverageFormatter.remaining(days: 89) == "89 days")
        #expect(CoverageFormatter.remaining(days: 34) == "34 days")
        #expect(CoverageFormatter.remaining(days: 8) == "8 days")
        #expect(CoverageFormatter.remaining(days: 6) == "6 days")
        #expect(CoverageFormatter.remaining(days: 1) == "1 day")
        #expect(CoverageFormatter.remaining(days: 0) == "today")
        #expect(CoverageFormatter.remaining(days: -3) == "expired")
    }

    @Test func leftSuffixSkipsTodayAndExpired() {
        #expect(CoverageFormatter.remainingLeft(days: 321) == "10 mo left")
        #expect(CoverageFormatter.remainingLeft(days: 34) == "34 days left")
        #expect(CoverageFormatter.remainingLeft(days: 0) == "today")
        #expect(CoverageFormatter.remainingLeft(days: -1) == "expired")
    }

    @Test func pastPhrasing() {
        #expect(CoverageFormatter.past(daysAgo: 120) == "4 mo ago")
        #expect(CoverageFormatter.past(daysAgo: 12) == "12 days ago")
        #expect(CoverageFormatter.past(daysAgo: 0) == "today")
    }

    @Test func absoluteDatesGainAYearBeyondSixMonths() {
        let calendar = Calendar.current
        let asOf = Date(timeIntervalSince1970: 1_752_000_000)
        let near = calendar.date(byAdding: .day, value: 40, to: asOf)!
        let far = calendar.date(byAdding: .day, value: 321, to: asOf)!
        #expect(!CoverageFormatter.absoluteDate(near, asOf: asOf).contains("20"))
        #expect(CoverageFormatter.absoluteDate(far, asOf: asOf).contains("20"))
    }

    @Test func daysLeftIsAnchoredToStartOfDay() {
        let calendar = Calendar.current
        let morning = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_752_000_000)).addingTimeInterval(3600)
        let lateSameDayTomorrow = calendar.date(byAdding: .day, value: 1, to: morning)!.addingTimeInterval(60_000)
        #expect(CoverageFormatter.daysLeft(from: morning, to: lateSameDayTomorrow) == 1)
    }
}

/// BUILD_REVIEW B5 — OCR shouting is a display problem, not a data problem.
struct DisplayNameTests {

    @Test func shoutingProductNamesGetTitleCased() {
        #expect(PTDisplayName.product("RHEEM STORAGE HEATER 20L") == "Rheem Storage Heater 20L")
        #expect(PTDisplayName.product("SONY BRAVIA TV") == "Sony Bravia TV")
    }

    @Test func typedNamesPassThroughUntouched() {
        #expect(PTDisplayName.product("iPhone 15 Pro") == "iPhone 15 Pro")
        #expect(PTDisplayName.product("MacBook Air") == "MacBook Air")
    }

    @Test func merchantsCutAtFirstLegalSuffix() {
        #expect(PTDisplayName.merchant("GAIN CITY BEST-ELECTRIC PTE LTD") == "Gain City Best-Electric")
        #expect(PTDisplayName.merchant("Apple Store") == "Apple Store")
    }

    @Test func merchantNeverCollapsesToEmpty() {
        // A vendor that IS just a legal suffix keeps its one token (the cut
        // only applies after something displayable) — it still gets
        // un-shouted like any other all-caps name.
        #expect(PTDisplayName.merchant("LTD") == "Ltd")
    }

    @Test func glyphAuditWaterHeaterIsNotATeacup() {
        #expect(ptGlyph(category: "Kitchen appliance", productName: "RHEEM STORAGE HEATER 20L") == "heater.vertical")
        #expect(ptGlyph(category: nil, productName: "Water Heater") == "heater.vertical")
        #expect(ptGlyph(category: nil, productName: "Espresso machine") == "cup.and.saucer")
        #expect(ptGlyph(category: "Mystery", productName: "Unknowable") == "shippingbox")
    }

    @Test func glyphKitchenHeatSplitsIntoThreeTiles() {
        // One receipt often carries oven + hob + stove; identical tiles read
        // as a copy-paste bug (Gain City receipt, build 47 feedback).
        #expect(ptGlyph(category: "Appliance", productName: "Brandt Built In Oven 73L") == "oven")
        #expect(ptGlyph(category: "Appliance", productName: "Brandt Induction Hob") == "cooktop")
        #expect(ptGlyph(category: "Appliance", productName: "Brandt Gas HOB-1 Burner") == "cooktop")
        #expect(ptGlyph(category: nil, productName: "Gas stove") == "stove")
        #expect(ptGlyph(category: nil, productName: "Bosch Dishwasher") == "dishwasher")
        // "Microwave oven" stays a microwave — the more specific word wins.
        #expect(ptGlyph(category: nil, productName: "Samsung Microwave Oven") == "microwave")
    }

    @Test func keywordCategoryBeatsEmbeddingDrift() {
        // The exact build-46 misfire: "STORAGE Heater" drifted to Home via
        // the "storage box" exemplar. Keywords are deterministic.
        #expect(CategoryClassifier.keywordCategory("RHEEM STORAGE HEATER 20L") == "Appliance")
        #expect(CategoryClassifier.keywordCategory("Brandt Induction Hob") == "Appliance")
        #expect(CategoryClassifier.keywordCategory("LG WASHER/DRYER - 10/6KG") == "Appliance")
    }

    @Test func keywordCategoryStaysOutWhenAmbiguousOrUnknown() {
        // Two categories match ("coffee" Kitchen + "table" Furniture) →
        // stand down and let embeddings decide.
        #expect(CategoryClassifier.keywordCategory("Coffee table") == nil)
        // "Nespresso" carries "espresso" — substring match is intended here.
        #expect(CategoryClassifier.keywordCategory("Nespresso Vertuo") == "Kitchen")
        // No keyword at all → nil (embedding fallback handles novelty).
        #expect(CategoryClassifier.keywordCategory("Lego Star Wars set") == nil)
        #expect(CategoryClassifier.keywordCategory("Gift voucher") == nil)
    }
}
