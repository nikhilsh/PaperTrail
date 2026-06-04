import Foundation

/// Determines how *ambiguous* numeric dates (e.g. `03/05/2025`) should be read,
/// based on the device's region — so a receipt scanned in the US is read
/// month-first while one in Singapore/UK is read day-first, instead of
/// hardcoding one convention for everyone.
///
/// The signal is the locale's own short-date field order (what `03/05/2025`
/// means to that region), derived from the localized date template rather than
/// a hand-maintained country list.
struct LocaleDateConvention: Equatable {

    enum Order: Equatable { case dayFirst, monthFirst, yearFirst }

    let order: Order

    static var current: LocaleDateConvention { LocaleDateConvention(locale: .current) }

    init(order: Order) { self.order = order }

    init(locale: Locale) {
        // e.g. en_US → "M/d/y", en_GB → "d/M/y", ja_JP → "y/MM/dd".
        let template = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "d/M/y"
        self.order = Self.order(fromTemplate: template)
    }

    /// First of the day/month/year field letters in a localized date pattern.
    static func order(fromTemplate template: String) -> Order {
        for char in template {
            switch char {
            case "d", "D": return .dayFirst
            case "M", "L": return .monthFirst
            case "y", "Y", "u": return .yearFirst
            default: continue
            }
        }
        return .dayFirst
    }

    var isMonthFirst: Bool { order == .monthFirst }

    /// Day-first ordering covers most of the world; year-first regions (e.g. JP)
    /// still print receipts day-or-month-first often, so for tie-breaking we
    /// treat year-first like day-first.
    var prefersMonthBeforeDay: Bool { order == .monthFirst }

    /// One line for the model prompt describing the expected order, with an example.
    var promptDescription: String {
        switch order {
        case .monthFirst:
            return "month-first (MM/DD/YYYY) — e.g. 03/05/2025 means 5 March 2025"
        case .dayFirst, .yearFirst:
            return "day-first (DD/MM/YYYY) — e.g. 03/05/2025 means 3 May 2025"
        }
    }
}
