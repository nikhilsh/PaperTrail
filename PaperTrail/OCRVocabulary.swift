import Foundation

/// Shared domain vocabulary for OCR and extraction.
///
/// Receipts are dense with brand and model tokens that Vision's language
/// correction "fixes" into nonsense ("Dyson" → "Dylan", "MUJI" → "Mug").
/// Seeding `VNRecognizeTextRequest.customWords` with these tokens biases the
/// recognizer toward the spellings we actually care about — an immediate,
/// zero-risk accuracy win on exactly the fields users correct most.
///
/// This is also the single source of truth for the brand lexicon used by the
/// heuristic extractor, so the two never drift apart.
enum OCRVocabulary {

    /// Well-known consumer electronics / appliance / lifestyle brands.
    /// Lowercased for case-insensitive substring matching in the heuristics.
    static let brands: Set<String> = [
        "samsung", "apple", "sony", "lg", "dyson", "panasonic", "philips",
        "bosch", "siemens", "miele", "braun", "asus", "acer", "dell", "hp",
        "lenovo", "microsoft", "google", "bose", "jbl", "harman",
        "whirlpool", "electrolux", "hitachi", "toshiba", "sharp",
        "daikin", "mitsubishi", "fujitsu", "nikon", "canon", "olympus",
        "garmin", "fitbit", "xiaomi", "huawei", "oppo", "vivo",
        "nintendo", "playstation", "xbox", "razer", "logitech",
        "breville", "delonghi", "kitchenaid", "cuisinart", "tefal",
        "ikea", "muji", "osim", "ogawa",
    ]

    /// Short brand names that survive the heuristics' "too short / all caps"
    /// junk gates. Kept in display casing because they double as `customWords`.
    static let shortBrands: Set<String> = [
        "3M", "HP", "LG", "BQ", "JBL", "UE",
        "IKEA", "Sony", "Acer", "Asus", "Dell",
        "Bose", "Dyson", "Nike", "Zara", "H&M",
        "MUJI", "Braun", "Miele", "Smeg", "Bosch",
    ]

    /// Common retailers / merchants in our primary market (Singapore + APAC).
    /// These show up as store names at the top of receipts and benefit from the
    /// same recognition bias as product brands.
    static let merchants: Set<String> = [
        "Harvey Norman", "Courts", "Challenger", "Best Denki", "Gain City",
        "Lazada", "Shopee", "Amazon", "Apple Store", "Mustafa",
        "Audio House", "Mega Discount Store", "Parisilk", "Sprint-Cass",
    ]

    /// Display-cased brand tokens suitable for `VNRecognizeTextRequest.customWords`.
    /// Vision matches these case-insensitively but we provide canonical casing.
    static let brandCustomWords: [String] = {
        // Title-case the lowercase brand set (e.g. "samsung" → "Samsung") and
        // union with the already-cased short brands and merchant names.
        let titled = brands.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return Array(Set(titled).union(shortBrands).union(merchants)).sorted()
    }()

    /// Build the full `customWords` list for a recognition request.
    ///
    /// - Parameter learnedMerchants: merchant display names accumulated by the
    ///   learning loop (`MerchantProfile.displayName`). Promoting these into the
    ///   recognizer closes the loop between learned data and OCR accuracy.
    static func customWords(learnedMerchants: [String] = []) -> [String] {
        guard !learnedMerchants.isEmpty else { return brandCustomWords }
        let cleaned = learnedMerchants
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        return Array(Set(brandCustomWords).union(cleaned)).sorted()
    }
}
