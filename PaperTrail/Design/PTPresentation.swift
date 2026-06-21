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
    case has(["wash", "dryer", "laundry"]): return "washer"
    case has(["speaker", "soundbar", "audio", "hifi", "headphone", "earbud", "airpod"]): return "hifispeaker"
    case has(["cook", "stove", "oven", "hob", "cooktop", "range"]): return "cooktop"
    case has(["coffee", "espresso", "kettle", "blender", "mixer", "kitchen"]): return "cup.and.saucer"
    case has(["camera", "lens", "gopro"]): return "camera"
    case has(["console", "playstation", "xbox", "nintendo", "game"]): return "gamecontroller"
    case has(["thermo", "heater", "aircon", "hvac", "climate"]): return "thermometer.medium"
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

        // Remaining-time phrasing
        switch status {
        case .expired:
            if let expiry { self.remainingShort = "Expired " + PTWarranty.relativePast(expiry) }
            else { self.remainingShort = "Expired" }
            self.pillText = "Expired"
            self.stampText = "Out of warranty"
        case .active, .expiringSoon:
            let phrase = expiry.map { PTWarranty.relativeFuture($0) } ?? "covered"
            self.remainingShort = "\(phrase) left"
            if status == .expiringSoon {
                self.pillText = "Expires in \(phrase)"
                self.stampText = "Expiring"
            } else {
                self.pillText = "Covered · \(phrase) left"
                self.stampText = "Under warranty"
            }
        case .unknown:
            self.remainingShort = "No warranty"
            self.pillText = "No warranty"
            self.stampText = "No warranty"
        }
    }

    /// "9 mo", "28 days", "2 yr" — coarse future distance to `date`.
    static func relativeFuture(_ date: Date) -> String {
        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0)
        return coarse(days)
    }

    /// "4 mo ago", "12 days ago" — coarse past distance from `date`.
    static func relativePast(_ date: Date) -> String {
        let days = max(0, Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0)
        return coarse(days) + " ago"
    }

    private static func coarse(_ days: Int) -> String {
        if days >= 365 {
            let yr = days / 365
            return "\(yr) yr"
        } else if days >= 60 {
            return "\(days / 30) mo"
        } else if days >= 14 {
            return "\(days / 7) wk"
        } else {
            return "\(days) day\(days == 1 ? "" : "s")"
        }
    }
}
