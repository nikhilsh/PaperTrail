import Foundation

/// Presentation-only cleanup of OCR-shaped names (BUILD_REVIEW B5): cards
/// and heroes show "Rheem Storage Heater 20L" and "Gain City", while the
/// raw scanned strings stay untouched on the record (and visible in
/// Details → Model). No model schema involved — pure string display logic.
enum PTDisplayName {
    /// Title-cases an ALL-CAPS OCR product name for display; a name the
    /// user typed (mixed case) passes through untouched.
    static func product(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isShouting(trimmed) else { return trimmed }
        return titleCased(trimmed)
    }

    /// Vendor display name: cut at the first legal-suffix token ("PTE",
    /// "LTD", …) so "GAIN CITY BEST-ELECTRIC PTE LTD" reads "Gain City
    /// Best-Electric" — a whole-token cut, never a mid-word ellipsis
    /// (that's the card's `lineLimit` job, which this exists to avoid
    /// triggering). Un-shouts the result like `product(_:)`.
    static func merchant(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(separator: " ").map(String.init)
        var kept: [String] = []
        for token in tokens {
            let bare = token.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,()"))
            if legalSuffixes.contains(bare), !kept.isEmpty { break }
            kept.append(token)
        }
        let shortened = kept.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—,"))
        let result = shortened.isEmpty ? trimmed : shortened
        return isShouting(result) ? titleCased(result) : result
    }

    /// Legal/corporate suffixes that end the display-worthy part of a vendor
    /// name. Compared against uppercased, punctuation-stripped tokens.
    private static let legalSuffixes: Set<String> = [
        "PTE", "LTD", "LLC", "LLP", "INC", "CO", "CORP", "CORPORATION",
        "COMPANY", "GMBH", "SDN", "BHD", "PLC", "PVT", "SA", "BV", "AG",
        "KK", "LIMITED", "INCORPORATED", "ENTERPRISE", "ENTERPRISES",
    ]

    /// A string is "shouting" when it has at least 3 letters and virtually
    /// all of them are uppercase — the OCR signature. "iPhone 15 Pro" and
    /// "Gain City" are left alone.
    private static func isShouting(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.count >= 3 else { return false }
        let uppers = letters.filter { CharacterSet.uppercaseLetters.contains($0) }
        return Double(uppers.count) / Double(letters.count) >= 0.9
    }

    private static func titleCased(_ text: String) -> String {
        text.split(separator: " ").map { token -> String in
            let word = String(token)
            if keepUppercased.contains(word.uppercased()) { return word.uppercased() }
            // "20L", "55X90K" — tokens with digits keep OCR casing; the
            // capitalized form of a unit token is usually right anyway and
            // re-casing model numbers loses information.
            if word.contains(where: \.isNumber) { return word }
            // Hyphenated words title-case each half ("BEST-ELECTRIC" →
            // "Best-Electric").
            return word.split(separator: "-").map { $0.capitalized }.joined(separator: "-")
        }.joined(separator: " ")
    }

    /// Acronyms that should survive title-casing ("SONY BRAVIA TV" →
    /// "Sony Bravia TV", not "…Tv").
    private static let keepUppercased: Set<String> = [
        "TV", "LED", "OLED", "LCD", "UHD", "HD", "HDR", "USB", "SSD", "HDD",
        "PC", "AC", "DC", "UPS", "DVD", "GPS", "RGB", "AI", "VR", "AV", "PS",
    ]
}

extension PurchaseRecord {
    /// Display form of `productName` — see `PTDisplayName.product`. The raw
    /// OCR string stays in `productName` (shown in Details → Model).
    nonisolated var displayProductName: String { PTDisplayName.product(productName) }

    /// Display form of `merchantName` — see `PTDisplayName.merchant`.
    nonisolated var displayMerchantName: String? { merchantName.map(PTDisplayName.merchant) }
}
