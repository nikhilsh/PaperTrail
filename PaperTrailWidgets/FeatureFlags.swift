import Foundation

/// Mirrors `PaperTrail/FeatureFlags.swift` — the widget extension has no
/// access to the app target's sources (no shared framework between the two
/// targets), so this is a deliberately trimmed, duplicated copy: just the
/// flag list and the read-only check `shelfWidgets` needs from inside the
/// widget process. No display metadata, no setter — those only make sense in
/// the app target's Flags screen. Keep in sync with the app-side copy if the
/// flag list or key format ever changes.
enum Flag: String, CaseIterable {
    case shelfWidgets
    case multiCoverage
    case addSheetV2
    case serviceLedger
    case manualOnFile
    case recallWatch
    case passItOn
    case siriIntents
    case animPassV3
    case translate
}

/// Read-only feature-flag check for the widget extension. Reads the same App
/// Group suite (`group.nikhilsh.PaperTrail`) the app writes through
/// `FeatureFlags.setOn`, so a flag flipped on the Flags screen takes effect
/// on the next widget timeline reload without any extra plumbing.
enum FeatureFlags {
    static let appGroupIdentifier = "group.nikhilsh.PaperTrail"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    /// Hard-ON, unconditionally, in APPSTORE builds (v1.1 store pass) —
    /// mirrors the app target's `isOn` exactly.
    static func isOn(_ flag: Flag) -> Bool {
        #if APPSTORE
        return flag != .recallWatch
        #else
        return defaults.bool(forKey: key(for: flag))
        #endif
    }

    static func key(for flag: Flag) -> String { "flag.\(flag.rawValue)" }
}
