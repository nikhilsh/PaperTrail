import Foundation

/// A curated, on-device lookup of major consumer-electronics/appliance brands →
/// their public support contact. This is deliberately small and static — no
/// network calls, no fuzzy semantic matching. It exists to give the "Suggest
/// support contacts" toggle something to suggest instead of being dead wiring.
///
/// Confidence bar: `url` is included whenever the brand has one obvious global
/// support domain. `phone` is included ONLY when there's one number we're
/// highly confident is correct (e.g. a well-known US toll-free line). When in
/// doubt, leave phone `nil` — the caller only ever surfaces this as "best
/// guess, verify before calling."
enum SupportContactDirectory {

    struct Entry: Hashable {
        /// Normalized lookup key (lowercased, alphanumeric only).
        let key: String
        let displayName: String
        let url: String?
        let phone: String?
    }

    static let entries: [Entry] = [
        Entry(key: "apple", displayName: "Apple", url: "https://support.apple.com", phone: "1-800-275-2273"),
        Entry(key: "samsung", displayName: "Samsung", url: "https://www.samsung.com/support", phone: "1-800-726-7864"),
        Entry(key: "sony", displayName: "Sony", url: "https://www.sony.com/electronics/support", phone: nil),
        Entry(key: "lg", displayName: "LG", url: "https://www.lg.com/us/support", phone: "1-800-243-0000"),
        Entry(key: "dyson", displayName: "Dyson", url: "https://www.dyson.com/support", phone: nil),
        Entry(key: "bosch", displayName: "Bosch", url: "https://www.bosch-home.com/support", phone: nil),
        Entry(key: "philips", displayName: "Philips", url: "https://www.philips.com/support", phone: nil),
        Entry(key: "panasonic", displayName: "Panasonic", url: "https://www.panasonic.com/support", phone: nil),
        Entry(key: "dell", displayName: "Dell", url: "https://www.dell.com/support", phone: "1-800-624-9897"),
        Entry(key: "hp", displayName: "HP", url: "https://support.hp.com", phone: "1-800-474-6836"),
        Entry(key: "lenovo", displayName: "Lenovo", url: "https://support.lenovo.com", phone: nil),
        Entry(key: "asus", displayName: "Asus", url: "https://www.asus.com/support", phone: nil),
        Entry(key: "microsoft", displayName: "Microsoft", url: "https://support.microsoft.com", phone: "1-800-642-7676"),
        Entry(key: "google", displayName: "Google", url: "https://support.google.com/store", phone: nil),
        Entry(key: "nintendo", displayName: "Nintendo", url: "https://www.nintendo.com/support", phone: "1-800-255-3700"),
        Entry(key: "canon", displayName: "Canon", url: "https://www.usa.canon.com/support", phone: nil),
        Entry(key: "nikon", displayName: "Nikon", url: "https://www.nikonusa.com/en/service-and-support", phone: nil),
        Entry(key: "gopro", displayName: "GoPro", url: "https://gopro.com/help", phone: nil),
        Entry(key: "dji", displayName: "DJI", url: "https://www.dji.com/support", phone: nil),
        Entry(key: "garmin", displayName: "Garmin", url: "https://support.garmin.com", phone: nil),
        Entry(key: "jbl", displayName: "JBL", url: "https://www.jbl.com/support", phone: nil),
        Entry(key: "bose", displayName: "Bose", url: "https://www.bose.com/support", phone: "1-800-379-2073"),
        Entry(key: "sonos", displayName: "Sonos", url: "https://support.sonos.com", phone: nil),
        Entry(key: "logitech", displayName: "Logitech", url: "https://www.logitech.com/support", phone: nil),
        Entry(key: "anker", displayName: "Anker", url: "https://www.anker.com/pages/support", phone: nil),
        Entry(key: "belkin", displayName: "Belkin", url: "https://www.belkin.com/support", phone: nil),
        Entry(key: "ikea", displayName: "IKEA", url: "https://www.ikea.com/us/en/customer-service", phone: nil),
        Entry(key: "xiaomi", displayName: "Xiaomi", url: "https://www.mi.com/global/service/support", phone: nil),
        Entry(key: "tcl", displayName: "TCL", url: "https://www.tcl.com/us/en/support", phone: nil),
        Entry(key: "hisense", displayName: "Hisense", url: "https://www.hisense-usa.com/support", phone: nil),
        Entry(key: "sharp", displayName: "Sharp", url: "https://www.sharpusa.com/support", phone: nil),
        Entry(key: "electrolux", displayName: "Electrolux", url: "https://www.electrolux.com/support", phone: nil),
        Entry(key: "whirlpool", displayName: "Whirlpool", url: "https://www.whirlpool.com/services/support.html", phone: "1-866-698-2538"),
        Entry(key: "miele", displayName: "Miele", url: "https://www.miele.com/en/com/customer-service.htm", phone: nil),
        Entry(key: "delonghi", displayName: "De'Longhi", url: "https://www.delonghi.com/en-us/support", phone: nil),
        Entry(key: "nespresso", displayName: "Nespresso", url: "https://www.nespresso.com/us/en/customer-support", phone: "1-800-562-1465"),
        Entry(key: "breville", displayName: "Breville", url: "https://www.breville.com/support", phone: nil),
        Entry(key: "kitchenaid", displayName: "KitchenAid", url: "https://www.kitchenaid.com/support.html", phone: "1-800-541-6390"),
        Entry(key: "tefal", displayName: "Tefal", url: "https://www.tefal.com/support", phone: nil),
        Entry(key: "ninja", displayName: "Ninja", url: "https://www.ninjakitchen.com/support", phone: nil),
        Entry(key: "shark", displayName: "Shark", url: "https://www.sharkclean.com/support", phone: nil),
        Entry(key: "irobot", displayName: "iRobot", url: "https://homesupport.irobot.com", phone: nil),
        Entry(key: "roborock", displayName: "Roborock", url: "https://support.roborock.com", phone: nil),
        Entry(key: "braun", displayName: "Braun", url: "https://www.braunhousehold.com/support", phone: nil),
        Entry(key: "oralb", displayName: "Oral-B", url: "https://oralb.com/support", phone: nil),
        Entry(key: "razer", displayName: "Razer", url: "https://mysupport.razer.com", phone: nil),
        Entry(key: "corsair", displayName: "Corsair", url: "https://www.corsair.com/support", phone: nil),
        Entry(key: "seagate", displayName: "Seagate", url: "https://www.seagate.com/support", phone: nil),
        Entry(key: "westerndigital", displayName: "Western Digital", url: "https://support.wdc.com", phone: nil),
        Entry(key: "sandisk", displayName: "SanDisk", url: "https://www.sandisk.com/support", phone: nil),
        Entry(key: "tplink", displayName: "TP-Link", url: "https://www.tp-link.com/support", phone: nil),
        Entry(key: "netgear", displayName: "Netgear", url: "https://www.netgear.com/support", phone: nil),
        Entry(key: "ring", displayName: "Ring", url: "https://support.ring.com", phone: nil),
        Entry(key: "eufy", displayName: "Eufy", url: "https://support.eufy.com", phone: nil),
        Entry(key: "arlo", displayName: "Arlo", url: "https://www.arlo.com/support", phone: nil),
        Entry(key: "makita", displayName: "Makita", url: "https://www.makitatools.com/support", phone: nil),
        Entry(key: "dewalt", displayName: "DeWalt", url: "https://www.dewalt.com/support", phone: "1-800-433-9258"),
        Entry(key: "ryobi", displayName: "Ryobi", url: "https://www.ryobitools.com/support", phone: nil),
        Entry(key: "karcher", displayName: "Karcher", url: "https://www.karcher.com/support", phone: nil),
        Entry(key: "casio", displayName: "Casio", url: "https://support.casio.com", phone: nil),
    ]

    private static let byKey: [String: Entry] = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })

    /// Ordered prefix keys, longest first, so prefix matching prefers the most
    /// specific brand key over an accidental shorter substring collision.
    private static let orderedKeys: [String] = entries.map(\.key).sorted { $0.count > $1.count }

    /// Normalize a free-form brand/product token into a lookup key: lowercase,
    /// strip everything but letters/digits.
    static func normalize(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Best-guess brand match for a purchase record, given its merchant name
    /// and product name. Tries the merchant name first (exact, then prefix),
    /// then the first couple of tokens of the product name the same way.
    /// Pure, synchronous, on-device — no network, no semantic matching.
    static func match(merchantName: String?, productName: String?) -> Entry? {
        var candidates: [String] = []
        if let merchantName, !merchantName.isEmpty {
            candidates.append(merchantName)
        }
        if let productName {
            let tokens = productName
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .prefix(2)
            for token in tokens {
                candidates.append(String(token))
            }
        }

        for candidate in candidates {
            let key = normalize(candidate)
            guard !key.isEmpty else { continue }
            if let exact = byKey[key] {
                return exact
            }
        }
        for candidate in candidates {
            let key = normalize(candidate)
            guard !key.isEmpty else { continue }
            for brandKey in orderedKeys {
                // The forward direction (`key.hasPrefix(brandKey)`) is safe at
                // any length — it's the brand's own full key being a prefix of
                // a longer token (e.g. "boseheadphones" → "bose"). The reverse
                // direction (a short typed/parsed token being a prefix of a
                // longer brand key, e.g. "lg" via exact match, "mi" wrongly
                // hitting "microsoft"/"miele") needs a minimum length so a
                // two-letter token like "Le" (Le Creuset) or "Mi" (Mi Robot
                // Vacuum) can't accidentally collide with an unrelated brand.
                if key.hasPrefix(brandKey) || (key.count >= 4 && brandKey.hasPrefix(key)) {
                    return byKey[brandKey]
                }
            }
        }
        return nil
    }
}
