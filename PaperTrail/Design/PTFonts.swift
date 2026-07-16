import SwiftUI
import UIKit
import CoreText

/// Registers the bundled OFL fonts (Newsreader, IBM Plex Mono) at runtime and
/// vends `Font` values for the design system.
///
/// We register programmatically rather than via Info.plist `UIAppFonts` because
/// the target uses `GENERATE_INFOPLIST_FILE = YES` (no hand-edited plist).
///
/// - Serif content: **Newsreader** (variable; we drive the `wght`/`opsz` axes
///   directly via `UIFont` so 500/600 are real, not synthesized).
/// - Mono data: **IBM Plex Mono** (static Regular/Medium, referenced by
///   PostScript name).
enum PTFont {

    // PostScript names (verified from the TTF name tables).
    private static let serifRomanPS  = "Newsreader16pt-Regular"
    private static let serifItalicPS = "Newsreader16pt-Italic"
    private static let monoRegularPS = "IBMPlexMono-Regular"
    private static let monoMediumPS  = "IBMPlexMono-Medium"

    // Variable-font axis identifiers.
    private static let wghtAxis: Int = 0x77676874 // 'wght'
    private static let opszAxis: Int = 0x6F70737A // 'opsz'

    // MARK: Registration

    private static var didRegister = false

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        let names = ["Newsreader-Roman", "Newsreader-Italic", "IBMPlexMono-Regular", "IBMPlexMono-Medium"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: Serif (Newsreader)

    /// Newsreader at an exact variable weight (default 500). `opsz` tracks the
    /// point size for correct optical sizing. Scaled for Dynamic Type via
    /// `UIFontMetrics(forTextStyle: .body)` — `.body` is the closest match
    /// for how this is used across the app (headline-adjacent reading text
    /// at a range of fixed point sizes, not a single named text style), so
    /// every call site scales the same way without changing its signature.
    static func serif(_ size: CGFloat, weight: CGFloat = 500, italic: Bool = false) -> Font {
        let opsz = min(max(Double(size), 6), 72)
        let variations: [Int: CGFloat] = [wghtAxis: weight, opszAxis: CGFloat(opsz)]
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: italic ? serifItalicPS : serifRomanPS,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations
        ])
        let uiFont = UIFont(descriptor: descriptor, size: size)
        let scaled = UIFontMetrics(forTextStyle: .body).scaledFont(for: uiFont)
        return Font(scaled)
    }

    // MARK: Mono (IBM Plex Mono)

    /// `Font.custom(_:size:relativeTo:)` scales with Dynamic Type natively —
    /// `relativeTo: .body` for the same reason as `serif` above.
    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        Font.custom(medium ? monoMediumPS : monoRegularPS, size: size, relativeTo: .body)
    }
}

// MARK: - Semantic text styles
//
// The prototype leans on a handful of recurring type treatments. These modifiers
// bundle font + tracking + (optional) case so screens read cleanly.

extension View {
    /// Mono, uppercased, wide tracking — section labels & meta.
    func ptMonoLabel(_ size: CGFloat = 10, tracking: CGFloat = 2) -> some View {
        font(PTFont.mono(size, medium: true))
            .tracking(tracking * size / 10)   // ~0.2em at 10pt
            .textCase(.uppercase)
    }

    /// The "PaperTrail" wordmark treatment.
    func ptWordmark() -> some View {
        font(PTFont.mono(11, medium: true))
            .tracking(3.7)
            .textCase(.uppercase)
            .foregroundStyle(PT.gold)
    }
}
