import SwiftUI

// MARK: - Category → SF Symbol glyph

/// Maps a record's category/product to an SF Symbol glyph for tiles.
/// Falls back to a generic doc symbol. Purely presentational.
func ptGlyph(category: String?, productName: String = "") -> String {
    let hay = ((category ?? "") + " " + productName).lowercased()
    func has(_ words: [String]) -> Bool { words.contains { hay.contains($0) } }

    switch true {
    case has(["tv", "televis", "monitor", "display", "oled"]): return "tv"
    case has(["laptop", "macbook", "notebook", "computer", "pc"]): return "laptopcomputer"
    case has(["phone", "iphone", "android", "mobile"]): return "iphone"
    case has(["tablet", "ipad"]): return "ipad"
    case has(["watch", "wearable"]): return "applewatch"
    case has(["fridge", "refriger", "freezer"]): return "refrigerator"
    // Dishwasher before the laundry words — "dishWASHer" must not match "wash".
    case has(["dishwasher"]): return "dishwasher"
    case has(["wash", "dryer", "laundry"]): return "washer"
    case has(["speaker", "soundbar", "audio", "hifi", "headphone", "earbud", "airpod"]): return "hifispeaker"
    // Heaters/climate before the kitchen keywords — a "Kitchen appliance"
    // category or a water heater must never win the teacup (BUILD_REVIEW B6:
    // wrong-but-confident beats neutral, so specific matches come first).
    case has(["heater", "geyser", "boiler"]): return "heater.vertical"
    case has(["aircon", "air con", "hvac", "climate", "air purifier"]): return "air.conditioner.horizontal"
    case has(["microwave"]): return "microwave"
    // Kitchen heat gets three distinct glyphs — one receipt often carries an
    // oven AND a hob, and identical tiles read as a copy-paste bug.
    case has(["oven"]): return "oven"
    case has(["stove", "range"]): return "stove"
    case has(["cook", "hob", "cooktop", "induction"]): return "cooktop"
    case has(["coffee", "espresso", "kettle", "blender", "mixer"]): return "cup.and.saucer"
    case has(["camera", "lens", "gopro"]): return "camera"
    case has(["console", "playstation", "xbox", "nintendo", "game"]): return "gamecontroller"
    case has(["thermo"]): return "thermometer.medium"
    case has(["vacuum", "cleaner", "robot"]): return "fan"
    case has(["light", "lamp", "bulb"]): return "lightbulb"
    case has(["tool", "drill", "saw"]): return "wrench.and.screwdriver"
    case has(["car", "vehicle", "auto", "tyre", "tire"]): return "car"
    case has(["furnitur", "chair", "desk", "sofa", "table"]): return "chair.lounge"
    default: return "shippingbox"
    }
}

// MARK: - Date formatting

enum PTDate {
    static let monthYear: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
    }()
    static let dayMonthYear: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; return f
    }()
    static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
    }()
}

// MARK: - Warranty display model

/// Presentational warranty info computed from a record. All copy/strings/maths
/// for the redesigned warranty UI live here so screens stay declarative.
struct PTWarranty {
    let status: WarrantyStatus
    let glyph: String

    /// Fraction of the warranty window still remaining (0…1). 0 when expired/unknown.
    let progressRemaining: Double

    /// Fraction of the warranty window already elapsed (0…1). This is what the
    /// progress bars fill by (a "time consumed" meter that grows toward expiry),
    /// matching the design prototype's `pct`.
    var progressElapsed: Double { 1 - progressRemaining }

    /// Compact remaining-time phrase, e.g. "9 mo left", "28 days", "Expired".
    let remainingShort: String

    /// Pill text, e.g. "Covered · 9 mo left", "Expires in 28 days", "Expired".
    let pillText: String

    /// Big stamp verdict, e.g. "Under warranty" / "Expiring" / "Out of warranty".
    let stampText: String

    init(record: PurchaseRecord) {
        let status = record.warrantyStatus
        self.status = status
        self.glyph = ptGlyph(category: record.category, productName: record.productName)

        let now = Date.now
        let expiry = record.warrantyExpiryDate

        // Progress remaining
        if let expiry, let purchase = record.purchaseDate, expiry > purchase {
            let total = expiry.timeIntervalSince(purchase)
            let left = expiry.timeIntervalSince(now)
            self.progressRemaining = max(0, min(1, left / total))
        } else if status == .expired {
            self.progressRemaining = 0
        } else {
            self.progressRemaining = 0.5
        }

        // Remaining-time phrasing — all through `CoverageFormatter` so the
        // app, widgets, and notifications agree on units (BUILD_REVIEW W2).
        switch status {
        case .expired:
            if let expiry { self.remainingShort = "Expired " + PTWarranty.relativePast(expiry) }
            else { self.remainingShort = "Expired" }
            self.pillText = "Expired"
            self.stampText = "Out of warranty"
        case .active, .expiringSoon:
            let daysLeft = expiry.map { max(0, CoverageFormatter.daysLeft(from: now, to: $0)) }
            self.remainingShort = daysLeft.map { CoverageFormatter.remainingLeft(days: $0) } ?? "Covered"
            if status == .expiringSoon {
                if let daysLeft {
                    self.pillText = daysLeft == 0
                        ? "Expires today"
                        : "Expires in \(CoverageFormatter.remaining(days: daysLeft))"
                } else {
                    self.pillText = "Expiring"
                }
                self.stampText = "Expiring"
            } else {
                self.pillText = daysLeft.map { "Covered · \(CoverageFormatter.remainingLeft(days: $0))" } ?? "Covered"
                self.stampText = "Under warranty"
            }
        case .unknown:
            self.remainingShort = "No warranty"
            self.pillText = "No warranty"
            self.stampText = "No warranty"
        }
    }

    /// "9 mo", "28 days" — future distance to `date`, `CoverageFormatter` units.
    static func relativeFuture(_ date: Date) -> String {
        CoverageFormatter.remaining(days: max(0, CoverageFormatter.daysLeft(from: .now, to: date)))
    }

    /// "4 mo ago", "12 days ago" — past distance from `date`.
    static func relativePast(_ date: Date) -> String {
        CoverageFormatter.past(daysAgo: max(0, CoverageFormatter.daysLeft(from: date, to: .now)))
    }
}

// MARK: - Return-window display model

/// Presentational return-window info computed from a record. Colors reuse the
/// exact same tones as `WarrantyStatus` (sage/amber/gray) so the two status
/// systems read as one visual language.
struct PTReturnWindow {
    let status: ReturnWindowStatus

    /// Full sentence for the detail view, e.g. "Return window: 12 days left
    /// (until 21 Jul 2026)" or "Return window closed 3 Jul 2026". `nil` when
    /// there's no window tracked.
    let detailText: String?

    /// Short badge text for library cards — only set when `closingSoon`.
    let badgeText: String?

    let tone: Color
    let textColor: Color
    let background: Color

    init(record: PurchaseRecord) {
        let status = record.returnWindowStatus
        self.status = status
        let until = record.returnDeadline.map { PTDate.dayMonthYear.string(from: $0) }

        switch status {
        case .none:
            detailText = nil
            badgeText = nil
            tone = PT.txt3
            textColor = PT.txt2
            background = Color(hex: 0xE7DCC4, alpha: 0.07)
        case .open(let daysLeft):
            detailText = "Return window: \(daysLeft) day\(daysLeft == 1 ? "" : "s") left (until \(until ?? "—"))"
            badgeText = nil
            tone = PT.sage
            textColor = Color(hex: 0xCFE0B0)
            background = Color(hex: 0x93A86F, alpha: 0.14)
        case .closingSoon(let daysLeft):
            detailText = "Return window: \(daysLeft) day\(daysLeft == 1 ? "" : "s") left (until \(until ?? "—"))"
            badgeText = "Return: \(daysLeft)d left"
            tone = PT.amber
            textColor = Color(hex: 0xF0D49A)
            background = Color(hex: 0xD7A64C, alpha: 0.15)
        case .closed:
            detailText = "Return window closed \(until ?? "—")"
            badgeText = nil
            tone = PT.txt3
            textColor = PT.txt2
            background = Color(hex: 0xE7DCC4, alpha: 0.07)
        }
    }
}
