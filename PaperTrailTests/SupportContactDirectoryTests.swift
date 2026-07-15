import Testing
@testable import PaperTrail

/// Verifies the brand-matching logic behind the "Suggest support contacts"
/// toggle: exact + prefix matching against the curated brand table, and that
/// matching stays a pure, on-device lookup (no network, no fuzzy semantics).
struct SupportContactDirectoryTests {

    @Test func normalizeLowercasesAndStripsPunctuation() {
        #expect(SupportContactDirectory.normalize("De'Longhi") == "delonghi")
        #expect(SupportContactDirectory.normalize("  Apple  ") == "apple")
        #expect(SupportContactDirectory.normalize("TP-Link") == "tplink")
    }

    @Test func matchesExactMerchantName() {
        let entry = SupportContactDirectory.match(merchantName: "Apple", productName: "iPhone 17 Pro")
        #expect(entry?.key == "apple")
        #expect(entry?.phone == "1-800-275-2273")
    }

    @Test func matchIsCaseAndWhitespaceInsensitive() {
        let entry = SupportContactDirectory.match(merchantName: "  sAmSuNg  ", productName: nil)
        #expect(entry?.key == "samsung")
    }

    @Test func fallsBackToProductNameTokenWhenMerchantUnknown() {
        // Bought from a third-party retailer, but the product name carries the brand.
        let entry = SupportContactDirectory.match(merchantName: "Best Buy", productName: "Dyson V15 Detect")
        #expect(entry?.key == "dyson")
    }

    @Test func prefixMatchHandlesTrailingModelSuffix() {
        let entry = SupportContactDirectory.match(merchantName: nil, productName: "Boseheadphones 700")
        #expect(entry?.key == "bose")
    }

    @Test func returnsNilWhenNoBrandRecognized() {
        let entry = SupportContactDirectory.match(merchantName: "Generic Mart", productName: "Widget 3000")
        #expect(entry == nil)
    }

    @Test func everyEntryHasAUniqueNonEmptyKeyAndURL() {
        let keys = SupportContactDirectory.entries.map(\.key)
        #expect(Set(keys).count == keys.count)
        for entry in SupportContactDirectory.entries {
            #expect(!entry.key.isEmpty)
            #expect(entry.url != nil)
        }
    }

    @Test func phoneOnlyPresentWhereCurated() {
        // Spot-check a brand we intentionally left phone-less because there's
        // no single confident global number.
        let entry = SupportContactDirectory.match(merchantName: "Sony", productName: nil)
        #expect(entry?.phone == nil)
        #expect(entry?.url != nil)
    }
}
