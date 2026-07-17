//
//  PTCurrency.swift
//  PaperTrail
//
//  Central source of truth for the currency code used when a record has none
//  stored (a scan whose extraction couldn't determine a currency, a blank
//  draft, an empty library). Previously five call sites each hardcoded
//  "SGD" as the fallback — correct for PaperTrail's original Singapore user
//  base, but wrong for anyone else. This resolves the fallback from the
//  device's own region instead, while still defaulting to SGD when the
//  locale doesn't resolve a currency (e.g. simulator/CI locales).
//
//  Display-time only: nothing here touches a record's persisted `currency`.
//

import Foundation

enum PTCurrency {
    /// The device's current currency code (e.g. "JPY", "USD"), falling back
    /// to "SGD" when `Locale.current` doesn't resolve one.
    static var deviceDefault: String {
        Locale.current.currency?.identifier ?? "SGD"
    }
}
