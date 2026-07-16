import SwiftUI

/// Tiny standalone palette for the widget extension. Deliberately not
/// sharing `PT`/`PTTheme` from the app target — there's no shared framework
/// between targets, and the widget doesn't need the app's full theme, just
/// these few colors.
enum WidgetPalette {
    /// Dark warm background.
    static let background = Color(red: 0x14 / 255, green: 0x12 / 255, blue: 0x10 / 255)
    /// Primary text.
    static let cream = Color(red: 0xEF / 255, green: 0xE6 / 255, blue: 0xD2 / 255)
    /// Default accent, healthy/far-out dates.
    static let gold = Color(red: 0xC2 / 255, green: 0xA1 / 255, blue: 0x5C / 255)
    /// Due within a week.
    static let amber = Color(red: 0xD9 / 255, green: 0x8A / 255, blue: 0x3D / 255)
    /// Due today or already past.
    static let terra = Color(red: 0xB5 / 255, green: 0x4A / 255, blue: 0x3C / 255)

    // MARK: - Paper (v3 shelfWidgets — Ideas C1)
    //
    // The medium "Closing soon" card and small coverage ring render on a
    // cream/paper background rather than the dark one above. Hex values are
    // the literal ones used in the C1 mock's `.wgt` gradient and ring stroke
    // (`docs/design-v3/"PaperTrail v3 Ideas.html"`); `ink`/`inkSecondary`/
    // `inkTertiary`/`goldDeep` approximate the mock's `--on-paper`/
    // `--on-paper-2`/`--on-paper-3`/`--gold-deep` CSS custom properties,
    // whose literal values live outside this repo (no `DESIGN_LANGUAGE.md`
    // checked in yet) — derived from the one literal ink rgba the mock does
    // use (`rgba(33,28,18,…)` for hairlines/the ring track) plus this
    // palette's existing `gold`, darkened for legibility on cream. Flag as
    // approximate for design sign-off once `DESIGN_LANGUAGE.md` lands.
    static let paperTop = Color(red: 0xF6 / 255, green: 0xEE / 255, blue: 0xDD / 255)
    static let paperBottom = Color(red: 0xED / 255, green: 0xE2 / 255, blue: 0xC8 / 255)
    /// Primary ink text on paper.
    static let ink = Color(red: 0x21 / 255, green: 0x1C / 255, blue: 0x12 / 255)
    /// Secondary ink (row subtitles) — approximated as `ink` at reduced
    /// opacity; see note above.
    static let inkSecondary = ink.opacity(0.68)
    /// Tertiary ink (captions) — approximated as `ink` at reduced opacity.
    static let inkTertiary = ink.opacity(0.45)
    /// Deeper, higher-contrast gold for kickers/CTAs against the cream
    /// background — approximated by darkening `gold`; see note above.
    static let goldDeep = Color(red: 0x8C / 255, green: 0x74 / 255, blue: 0x40 / 255)
    /// Coverage-ring fill — literal hex from the C1 mock's ring stroke.
    static let sage = Color(red: 0x93 / 255, green: 0xA8 / 255, blue: 0x6F / 255)
    /// Coverage-ring track (unfilled arc) — literal rgba from the mock.
    static let ringTrack = ink.opacity(0.12)
}
