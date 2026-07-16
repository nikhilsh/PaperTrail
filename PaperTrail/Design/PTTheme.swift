import SwiftUI

// MARK: - Color hex helper

extension Color {
    /// Create a Color from a 0xRRGGBB hex literal (optionally with alpha).
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - "The Archive" design tokens
//
// Warm-dark, paper-archival identity. Colors are fixed (non-adaptive): the app
// presents a single dark canvas, so these never flip with the system appearance.
// The root view forces `.preferredColorScheme(.dark)` so native controls
// (date pickers, Sign in with Apple, share sheet) render correctly on the canvas.

enum PT {

    // MARK: Ink (dark grounds)
    static let inkCanvas   = Color(hex: 0x0E0C09) // warm near-black app background — NOT pure black
    static let inkPanel    = Color(hex: 0x13110D) // tab bar base / raised
    static let inkRaised   = Color(hex: 0x191510) // raised dark surface
    static let inkCardDark  = Color(hex: 0x221C15) // dark card
    static let inkStamp    = Color(hex: 0x2A2110) // stamp / pill background on dark

    // MARK: Paper (cream surfaces)
    static let paper       = Color(hex: 0xF3EBD9) // primary cream surface
    static let paperTop    = Color(hex: 0xF6EEDD) // filing-card gradient top
    static let paperMid    = Color(hex: 0xF0E7D2) // filing-card gradient mid
    static let paperBottom  = Color(hex: 0xE9DEC5) // filing-card gradient bottom
    static let paperFold   = Color(hex: 0xD6C7A2) // dog-ear fold (when not gold)

    // MARK: Ink text on cream
    static let onPaper     = Color(hex: 0x211C12) // primary ink text on cream
    static let onPaper2    = Color(hex: 0x5F5641) // secondary text on cream
    static let onPaper3    = Color(hex: 0x7C7257) // tertiary / mono meta on cream

    // MARK: Parchment text on dark
    static let txt         = Color(hex: 0xEFE6D2) // primary text on dark
    static let txt2        = Color(hex: 0xC2B89E) // secondary text on dark
    static let txt3        = Color(hex: 0x938A70) // tertiary text on dark

    // MARK: Hairlines
    static let hair        = Color(hex: 0xE7DCC4, alpha: 0.14) // divider on dark
    static let hair2       = Color(hex: 0xE7DCC4, alpha: 0.08) // subtle (tab bar top)
    static let onPaperHair = Color(hex: 0x211C12, alpha: 0.10) // divider on cream

    // MARK: Gold (brand foil accent)
    static let gold        = Color(hex: 0xC2A15C)
    static let goldHi      = Color(hex: 0xE0C588)
    static let goldHi2     = Color(hex: 0xF0DCA4)
    static let goldDeep    = Color(hex: 0x8A6E3A)

    // MARK: Status (reserved — derived ONLY from warrantyStatus, never a brand color)
    static let sage        = Color(hex: 0x93A86F) // covered / resting easy
    static let sageDeep    = Color(hex: 0x6E8550)
    static let amber       = Color(hex: 0xD7A64C) // expiring soon
    static let terra       = Color(hex: 0xC56A45) // expired / at-risk

    // MARK: - Metrics
    enum Metric {
        static let cardRadius: CGFloat = 14
        static let pillRadius: CGFloat = 11
        static let buttonRadius: CGFloat = 11
        static let glyphRadius: CGFloat = 9
        static let screenPad: CGFloat = 22   // list side padding
        static let detailPad: CGFloat = 16   // detail / nav side padding
        static let cardGap: CGFloat = 14
        static let dogEar: CGFloat = 20
    }

    // MARK: - Gradients
    static let paperFill = LinearGradient(
        colors: [paperTop, paperMid, paperBottom],
        startPoint: .top, endPoint: .bottom
    )

    /// Horizontal foil gradient used for the gold-rule underline and dog-ear fold.
    static let goldFoil = LinearGradient(
        stops: [
            .init(color: goldDeep, location: 0.0),
            .init(color: gold,     location: 0.38),
            .init(color: goldHi,   location: 0.5),
            .init(color: gold,     location: 0.62),
            .init(color: goldDeep, location: 1.0)
        ],
        startPoint: .leading, endPoint: .trailing
    )

    /// Soft top-gold / bottom-shadow vignette painted behind every screen.
    static let canvasVignette = RadialGradient(
        colors: [gold.opacity(0.10), .clear],
        center: .top, startRadius: 0, endRadius: 460
    )

    /// The v2 foil gradient, stop-for-stop per `docs/design-v2/DESIGN_LANGUAGE.md`
    /// §2: `linear(90°, goldDeep, gold 40%, goldHi 52%, gold 64%, goldDeep)`.
    ///
    /// This is ~2% off `goldFoil`'s stops (38/50/62, taken from `pt.css`'s
    /// `.gold-rule` — the two source docs disagree by a couple of percentage
    /// points and neither reads as visually distinct at UI scale). `goldFoil`
    /// is left untouched so existing screens don't shift; new v2 work should
    /// prefer `foilGradient` as the named, spec-exact token.
    static let foilGradient = LinearGradient(
        stops: [
            .init(color: goldDeep, location: 0.0),
            .init(color: gold,     location: 0.40),
            .init(color: goldHi,   location: 0.52),
            .init(color: gold,     location: 0.64),
            .init(color: goldDeep, location: 1.0)
        ],
        startPoint: .leading, endPoint: .trailing
    )
}

// MARK: - Motion (docs/design-v2/ANIMATION_SPEC.md)

/// Named easing curves from the v2 animation spec, plus a Reduce Motion
/// escape hatch. Curves are parameterized by duration because the same curve
/// is reused at different durations across components (e.g. `archiveEase`
/// drives both the 280ms push transition and the 900ms coverage-ring sweep).
enum PTMotion {
    /// cubic-bezier(.2,.7,.3,1) — navigation push/pop, coverage ring sweep.
    static func archiveEase(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.7, 0.3, 1, duration: duration)
    }

    /// cubic-bezier(.2,.8,.25,1) — sheet presentation (soft-ask, paywall).
    static func sheetEase(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.8, 0.25, 1, duration: duration)
    }

    /// cubic-bezier(.2,.9,.3,1.3) — slight overshoot; the PURCHASED stamp slam.
    static func stampEase(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.9, 0.3, 1.3, duration: duration)
    }

    /// Per ANIMATION_SPEC "Don'ts": under Reduce Motion, every translation
    /// becomes a 200ms crossfade — no skew, no overshoot, no sheen. Pass the
    /// spec'd curve/duration plus the environment's `accessibilityReduceMotion`
    /// value; this returns the right `Animation` for the current context.
    static func reduced(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }
}
