import SwiftUI
import UIKit

// MARK: - Screen background

/// The warm-dark canvas + soft gold vignette that sits behind every screen.
struct ScreenBackground: View {
    var body: some View {
        ZStack {
            PT.inkCanvas
            PT.canvasVignette
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Place the standard dark canvas behind a screen's content.
    func ptScreen() -> some View {
        background(ScreenBackground())
    }

    /// "Done" above the keyboard — .decimalPad/.numberPad have no return key.
    func ptKeyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

// MARK: - Note fact chip

/// One extraction fact from a record's notes ("ORDER NO  IV-2081") — see
/// `NoteFacts`. Used by both detail views (owned and shared-in records).
struct NoteFactChip: View {
    let fact: NoteFacts.Fact

    var body: some View {
        HStack(spacing: 8) {
            Text(fact.label.uppercased())
                .ptMonoLabel(8.5, tracking: 1.2)
                .foregroundStyle(PT.txt3)
            Text(fact.value)
                .font(PTFont.mono(12, medium: true))
                .foregroundStyle(PT.txt)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 11)
        .background(Color(hex: 0xE7DCC4, alpha: 0.06), in: Capsule())
        .overlay(Capsule().stroke(PT.hair, lineWidth: 1))
    }
}

// MARK: - Dog-ear filing card

/// A rounded rectangle with the top-right corner folded down — the icon motif
/// made literal. Used to clip and fill every "filing card".
struct DogEarShape: Shape {
    var radius: CGFloat = PT.Metric.cardRadius
    var ear: CGFloat = PT.Metric.dogEar

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let e = min(ear, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - e, y: rect.minY))          // top edge to ear
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + e))          // diagonal cut
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The folded-corner triangle drawn over the cut. Gold foil on hero cards.
private struct DogEarFold: View {
    var ear: CGFloat = PT.Metric.dogEar
    var gold: Bool

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: ear, y: ear))
            p.addLine(to: CGPoint(x: 0, y: ear))
            p.closeSubpath()
        }
        .fill(gold
              ? AnyShapeStyle(PT.goldFoil)
              : AnyShapeStyle(LinearGradient(colors: [PT.paperFold, Color(hex: 0xC7B791)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
        .frame(width: ear, height: ear)
        .shadow(color: .black.opacity(0.18), radius: 1, x: -1, y: 1)
    }
}

extension View {
    /// Render `self` as a cream filing card: paper gradient, top sheen, shadow,
    /// folded top-right corner. `goldFold` makes the fold gold foil (hero cards).
    func paperCard(goldFold: Bool = true, ear: CGFloat = PT.Metric.dogEar) -> some View {
        let shape = DogEarShape(ear: ear)
        return self
            .background(PT.paperFill)
            .overlay(
                // faint top sheen
                LinearGradient(colors: [Color.white.opacity(0.18), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 26),
                alignment: .top
            )
            .clipShape(shape)
            .overlay(alignment: .topTrailing) { DogEarFold(ear: ear, gold: goldFold) }
            .overlay(shape.stroke(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.55), radius: 17, x: 0, y: 18)
            .shadow(color: .black.opacity(0.4), radius: 7, x: 0, y: 6)
    }
}

// MARK: - Camera corner brackets

/// Four L-shaped corner brackets (the viewfinder motif on the capture frame).
struct CornerBrackets: View {
    var color: Color = PT.gold
    var length: CGFloat = 26
    var thickness: CGFloat = 2
    var inset: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                // top-left
                p.move(to: CGPoint(x: inset, y: inset + length))
                p.addLine(to: CGPoint(x: inset, y: inset))
                p.addLine(to: CGPoint(x: inset + length, y: inset))
                // top-right
                p.move(to: CGPoint(x: w - inset - length, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset))
                p.addLine(to: CGPoint(x: w - inset, y: inset + length))
                // bottom-left
                p.move(to: CGPoint(x: inset, y: h - inset - length))
                p.addLine(to: CGPoint(x: inset, y: h - inset))
                p.addLine(to: CGPoint(x: inset + length, y: h - inset))
                // bottom-right
                p.move(to: CGPoint(x: w - inset - length, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset))
                p.addLine(to: CGPoint(x: w - inset, y: h - inset - length))
            }
            .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Gold rule

/// The 2pt foil underline accent.
struct GoldRule: View {
    var width: CGFloat? = nil
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(PT.goldFoil)
            .frame(width: width, height: 2)
    }
}

// MARK: - Status (warranty) presentation

extension WarrantyStatus {
    /// The semantic tone color, derived ONLY from warranty status.
    var tone: Color {
        switch self {
        case .active: PT.sage
        case .expiringSoon: PT.amber
        case .expired: PT.terra
        case .unknown: PT.txt3
        }
    }

    /// Brighter pill text tone for legibility on dark.
    var pillTextColor: Color {
        switch self {
        case .active: Color(hex: 0xCFE0B0)
        case .expiringSoon: Color(hex: 0xF0D49A)
        case .expired: Color(hex: 0xEAB69C)
        case .unknown: PT.txt2
        }
    }

    var pillBackground: Color {
        switch self {
        case .active: Color(hex: 0x93A86F, alpha: 0.14)
        case .expiringSoon: Color(hex: 0xD7A64C, alpha: 0.15)
        case .expired: Color(hex: 0xC56A45, alpha: 0.16)
        case .unknown: Color(hex: 0xE7DCC4, alpha: 0.07)
        }
    }

    /// Pill text for CREAM (paper-card) backgrounds — the dark-background
    /// tones above washed out to pale-on-pale there (BUILD_REVIEW B3).
    /// Deep variants keep ≥ 4.5:1 contrast on `PT.paper`.
    var pillTextColorOnPaper: Color {
        switch self {
        case .active: Color(hex: 0x6E8550)        // sageDeep
        case .expiringSoon: Color(hex: 0x8A6420)  // amberDeep
        case .expired: Color(hex: 0xA34F30)       // terraDeep
        case .unknown: PT.onPaper2
        }
    }

    var pillBackgroundOnPaper: Color {
        switch self {
        case .active: Color(hex: 0x93A86F, alpha: 0.18)
        case .expiringSoon: Color(hex: 0xD7A64C, alpha: 0.18)
        case .expired: Color(hex: 0xC56A45, alpha: 0.16)
        case .unknown: Color(hex: 0x211C12, alpha: 0.07)
        }
    }
}

/// Small dot + mono label, tinted by warranty status. `onPaper` switches to
/// the deep text tones that stay legible on cream cards (BUILD_REVIEW B3) —
/// the default palette is tuned for the dark background.
struct StatusPill: View {
    let status: WarrantyStatus
    var text: String
    var onPaper: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if status != .unknown {
                Circle()
                    .fill(status.tone)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .ptMonoLabel(10, tracking: 1.2)
        }
        .foregroundStyle(onPaper ? status.pillTextColorOnPaper : status.pillTextColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(onPaper ? status.pillBackgroundOnPaper : status.pillBackground, in: Capsule())
    }
}

/// Small dot + mono label, styled identically to `StatusPill` but driven by an
/// explicit tone/text/background rather than `WarrantyStatus` — used for
/// return-window badges, which have their own status type.
struct TonedStatusPill: View {
    let text: String
    var tone: Color
    var textColor: Color
    var background: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone)
                .frame(width: 6, height: 6)
            Text(text)
                .ptMonoLabel(10, tracking: 1.2)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(background, in: Capsule())
    }
}

// MARK: - Stamp badge

/// Rubber-stamp verdict: mono, letter-spaced, outlined, rotated ~-3°.
struct StampBadge: View {
    let text: String
    var tone: Color = PT.goldDeep
    /// Smaller variant for use inside dense cards (e.g. the Warranty dashboard).
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font(PTFont.mono(compact ? 9 : 12, medium: true))
            .tracking(compact ? 1.6 : 2.2)
            .textCase(.uppercase)
            .foregroundStyle(tone)
            .padding(.horizontal, compact ? 8 : 14)
            .padding(.vertical, compact ? 5 : 8)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tone, lineWidth: 2))
            .rotationEffect(.degrees(-3))
    }
}

// MARK: - Glyph tile

/// A category glyph (SF Symbol) in a bordered, rounded tile.
struct GlyphTile: View {
    let symbol: String
    var size: CGFloat = 38
    var onPaper: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: PT.Metric.glyphRadius, style: .continuous)
            .fill(onPaper ? Color(hex: 0x211C12, alpha: 0.06) : Color(hex: 0xE7DCC4, alpha: 0.05))
            .overlay(
                RoundedRectangle(cornerRadius: PT.Metric.glyphRadius, style: .continuous)
                    .stroke(onPaper ? Color(hex: 0x211C12, alpha: 0.10) : PT.hair, lineWidth: 1)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .regular))
                    .foregroundStyle(onPaper ? PT.onPaper2 : PT.txt2)
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Section label

/// Mono, uppercase, wide-tracked section header, optionally tinted.
struct SectionLabel: View {
    let text: String
    var tone: Color = PT.txt3

    var body: some View {
        Text(text)
            .ptMonoLabel(10.5, tracking: 2.4)
            .foregroundStyle(tone)
    }
}

// MARK: - Chip

struct Chip: View {
    var symbol: String? = nil
    let text: String
    var tone: Color = PT.txt2

    var body: some View {
        HStack(spacing: 7) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
            Text(text)
                .font(PTFont.mono(10.5))
                .tracking(0.8)
                .textCase(.uppercase)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(hex: 0xE7DCC4, alpha: 0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }
}

// MARK: - Attention banner

/// Gold-tinted banner that deep-links to the Warranty tab.
struct AttentionBanner: View {
    let count: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(PT.amber)
                Text("\(count) need attention — open the Warranty tab")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(hex: 0xF0D49A))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PT.amber)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(hex: 0xD7A64C, alpha: 0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0xD7A64C, alpha: 0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Warranty progress bar

/// A thin progress track whose fill is tinted by warranty tone.
struct WarrantyProgressBar: View {
    /// 0…1, fraction of the warranty window remaining (or elapsed — caller decides).
    let progress: Double
    var tone: Color
    var onPaper: Bool = true
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(onPaper ? Color(hex: 0x211C12, alpha: 0.10) : Color(hex: 0xE7DCC4, alpha: 0.10))
                Capsule()
                    .fill(LinearGradient(colors: [tone.opacity(0.7), tone], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Round icon button (back / share / edit)

struct RoundIconButton: View {
    let symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(PT.txt)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(PT.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Button styles

/// Primary gold foil button.
struct PTGoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PTFont.mono(12, medium: true))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(PT.inkStamp)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(
                LinearGradient(colors: [Color(hex: 0xF2EAD7), Color(hex: 0xE7DABC)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: PT.Metric.buttonRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PT.Metric.buttonRadius, style: .continuous)
                    .stroke(Color(hex: 0xC9B988), lineWidth: 1)
            )
            .shadow(color: PT.gold.opacity(0.5), radius: 12, x: 0, y: 12)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Outline button on dark.
struct PTOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PTFont.mono(12, medium: true))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(PT.txt)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .overlay(
                RoundedRectangle(cornerRadius: PT.Metric.buttonRadius, style: .continuous)
                    .stroke(configuration.isPressed ? PT.goldDeep : PT.hair, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Small dark action button used inside cream cards ("Get support", "Call", "Get help").
struct PTDarkButtonStyle: ButtonStyle {
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PTFont.mono(10.5, medium: true))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(Color(hex: 0xF2EAD7))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, fullWidth ? 12 : 10)
            .padding(.horizontal, 16)
            .background(PT.inkStamp, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
