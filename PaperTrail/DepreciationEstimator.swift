import Foundation

/// Straight-line depreciation estimate for a purchased item — powers the
/// "estimated value today" column in the Insurance-Ready Home Inventory
/// Report. Pure and `nonisolated`: no I/O, no SwiftData, no main-actor
/// requirement, so it's cheap to unit test and safe to call from anywhere.
nonisolated enum DepreciationEstimator {

    /// Straight-line annual depreciation rate, matched case-insensitively by
    /// substring against the record's free-form `category` string. Match
    /// keywords use singular roots so both "Appliance" (the app's own
    /// taxonomy, see CategoryClassifier) and "Appliances" match the same
    /// way. First match in this list wins; an unmatched (or nil/empty)
    /// category falls back to `defaultAnnualRate`.
    private static let categoryRates: [(match: String, rate: Double)] = [
        ("electronic", 0.25),
        ("computer", 0.25),
        ("phone", 0.25),
        ("appliance", 0.15),
        ("furniture", 0.15),
        ("tool", 0.10),
        ("jewelry", 0.0),
        ("watch", 0.0),
    ]
    private static let defaultAnnualRate = 0.10

    /// Never depreciate below this fraction of the original purchase price —
    /// even very old gear retains some resale/replacement-reference value.
    private static let floorFraction = 0.20

    /// Estimate what `amount` is worth today given `category` and how long
    /// ago it was purchased.
    /// - Returns `nil` when there's no purchase amount to depreciate.
    /// - A `purchaseDate` in the future clamps elapsed time to 0 years (no
    ///   depreciation), rather than producing a value above `amount`.
    /// - A `nil` `purchaseDate` is treated as 0 elapsed years (unknown age).
    static func estimatedCurrentValue(
        amount: Double?,
        category: String?,
        purchaseDate: Date?,
        asOf: Date = .now
    ) -> Double? {
        guard let amount else { return nil }
        let rate = annualRate(for: category)
        let years = elapsedYears(purchaseDate: purchaseDate, asOf: asOf)
        let depreciated = amount * (1 - rate * years)
        let floor = amount * floorFraction
        let value = max(depreciated, floor)
        return (value * 100).rounded() / 100
    }

    private static func annualRate(for category: String?) -> Double {
        guard let category, !category.trimmingCharacters(in: .whitespaces).isEmpty else {
            return defaultAnnualRate
        }
        let lower = category.lowercased()
        for (match, rate) in categoryRates where lower.contains(match) {
            return rate
        }
        return defaultAnnualRate
    }

    private static func elapsedYears(purchaseDate: Date?, asOf: Date) -> Double {
        guard let purchaseDate else { return 0 }
        let seconds = asOf.timeIntervalSince(purchaseDate)
        guard seconds > 0 else { return 0 } // future purchase date clamps to 0 years elapsed
        return seconds / (365.2425 * 86_400)
    }
}
