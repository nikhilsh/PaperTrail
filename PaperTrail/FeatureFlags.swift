import Foundation

/// The nine v3 features, each gated behind a flag — see
/// `docs/design-v3/V3_BRIEF.md` §0. Single source of truth for what v3 ships;
/// every v3 entry point checks `FeatureFlags.isOn(_:)` before rendering.
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
    /// Milestone: receipt translation. On-device only (`import Translation`)
    /// — detects the OCR text's dominant language with `NLLanguageRecognizer`
    /// and, if it differs from the user's preferred language and the pairing
    /// is supported, offers a translate affordance in `ImageViewerView`. Not
    /// part of the original v3 nine; added later behind the same pattern.
    case translate
}

/// Runtime feature-flag reads (and, outside APPSTORE builds, writes) for v3.
///
/// **Architectural change from the brief:** the brief specifies
/// `UserDefaults.standard`, but that suite is sandboxed per-process and
/// doesn't reach `PaperTrailWidgets` — v3 §1 `shelfWidgets` needs its flag
/// checked from inside the widget extension, a separate process with its own
/// `UserDefaults.standard`. Flags are read/written through the shared App
/// Group suite (`group.nikhilsh.PaperTrail`, already used by
/// `WidgetSnapshotWriter`) instead, so the app and the widget extension see
/// the same value. Falls back to `.standard` only if the App Group container
/// is ever unavailable (e.g. a misconfigured entitlement), so a flag check
/// never crashes.
///
/// `PaperTrailWidgets/FeatureFlags.swift` is a trimmed mirror of this file
/// (`Flag` + `isOn` only, no display metadata or setter) — there's no shared
/// framework between the two targets, so keep the two in sync if the flag
/// list or key format ever changes.
enum FeatureFlags {
    static let appGroupIdentifier = "group.nikhilsh.PaperTrail"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    /// Whether `flag` is on for this build. Hard-off, unconditionally, in
    /// APPSTORE builds — no remote override, no exceptions — so the App
    /// Store binary is provably v3-free regardless of what's stored in
    /// defaults.
    ///
    /// `suite` defaults to the shared App Group suite; tests inject a scratch
    /// `UserDefaults` so they never touch real device state.
    static func isOn(_ flag: Flag, suite: UserDefaults = FeatureFlags.defaults) -> Bool {
        #if APPSTORE
        return false
        #else
        return suite.bool(forKey: key(for: flag))
        #endif
    }

    #if !APPSTORE
    /// Flips `flag` for the Flags screen (Advanced & Diagnostics). Compiled
    /// out of APPSTORE builds along with every call site — there's no path
    /// to flip a flag in a build where `isOn` always returns `false`.
    static func setOn(_ isOn: Bool, for flag: Flag, suite: UserDefaults = FeatureFlags.defaults) {
        suite.set(isOn, forKey: key(for: flag))
    }

    /// Sets every flag to `isOn` in one pass — backs the Flags screen's
    /// ALL ON / ALL OFF / MATCH APP STORE (= all off) actions.
    static func setAll(_ isOn: Bool, suite: UserDefaults = FeatureFlags.defaults) {
        for flag in Flag.allCases { setOn(isOn, for: flag, suite: suite) }
    }
    #endif

    /// `UserDefaults` key for `flag` — stable format, covered by
    /// `FeatureFlagsTests`.
    static func key(for flag: Flag) -> String { "flag.\(flag.rawValue)" }
}

// MARK: - Flags screen display metadata (V3-3 mock)

extension Flag {
    /// Plain-language subtitle shown beneath the mono flag name on the Flags
    /// screen (`docs/design-v3/PaperTrail v3 Screens.html`, V3-3).
    var subtitle: String {
        switch self {
        case .shelfWidgets: "Home & lock screen widgets"
        case .multiCoverage: "Coverage lines per item"
        case .addSheetV2: "Five ways to shelve"
        case .serviceLedger: "Repairs timeline in dossier"
        case .manualOnFile: "PDF manuals per item"
        case .recallWatch: "Safety recall matching · Plus"
        case .passItOn: "Buyer resale packet · Plus"
        case .siriIntents: "Siri, Spotlight, App Intents"
        case .animPassV3: "Ten new motion moments"
        case .translate: "Translate receipts on-device"
        }
    }
}
