import SwiftUI

// MARK: - CertificateView (docs/design-v2/V2_BRIEF.md §3 P1, pt.css `.cert`/`.cert-in`/`.seal`)
//
// The paywall's hero content: a cream "certificate of membership" with a
// double engraved border, a gold seal, benefit checks, and a price area.
// Content-only — the paywall screen (Wave D) wires in StoreKit, the buy
// button, and the MEMBER ✓-stamp/gold-strike sequence.
//
// SPEC v2.1 (subscription-only; supersedes the brief's lifetime framing):
// the tagline reads "Renewed yearly, like a library card.", the seal says
// "PLUS · MEMBER · EST 2026", and the price area is a generic slot that
// Wave D fills with a two-plan picker built from `PlanPickerRow` +
// `PlanFinePrint` below (Annual default with ≈/month math, Monthly). The
// old "ONE TIME / No subscription. Nothing recurring, ever." copy is dead —
// nothing here hardcodes any plan shape.

struct CertificateView<PriceSlot: View>: View {
    var kicker: String = "Certificate of membership"
    var title: String = "PaperTrail Plus"
    /// v2.1 house copy: "Renewed yearly, like a library card." — caller-
    /// supplied so screens can localize/rephrase.
    var tagline: String
    /// The seal's caption lines. Default per spec v2.1.
    var sealCaption: String = "PLUS ·\nMEMBER\n· EST 2026"
    var benefits: [String]
    @ViewBuilder var priceSlot: () -> PriceSlot

    var body: some View {
        VStack(spacing: 0) {
            Text(kicker.uppercased())
                .ptMonoLabel(10, tracking: 2.4)
                .foregroundStyle(PT.goldDeep)

            Text(title)
                .font(PTFont.serif(34, weight: 600))
                .foregroundStyle(PT.onPaper)
                .padding(.top, 8)

            Text(tagline)
                .font(PTFont.serif(15, weight: 500, italic: true))
                .foregroundStyle(PT.onPaper2)
                .padding(.top, 6)

            seal
                .padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(benefits, id: \.self) { benefit in
                    HStack(alignment: .top, spacing: 10) {
                        Text("✓").foregroundStyle(PT.sageDeep)
                        Text(benefit)
                            .font(.system(size: 13))
                            .foregroundStyle(PT.onPaper)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 262)

            GoldRule(width: 180)
                .padding(.vertical, 16)

            priceSlot()
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity)
        .overlay(outerBorder)   // gold border wraps the padded content directly
        .overlay(innerBorder)   // thin inner line, inset 4pt inside the gold border
        .padding(6)             // cream gap between the gold border box and the outer card edge
        .background(certBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Seal (pt.css `.seal`)

    private var seal: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: 0xE0C588), PT.gold, PT.goldDeep],
                    center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 44
                ))
            Circle()
                .strokeBorder(Color(hex: 0x2A2110, alpha: 0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .padding(6)
            Text(sealCaption)
                .font(PTFont.mono(8, medium: true))
                .tracking(1.6)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0x2A2110))
                .lineSpacing(2)
        }
        .frame(width: 74, height: 74)
        .shadow(color: Color(hex: 0x8A6E3A, alpha: 0.7), radius: 9, x: 0, y: 6)
    }

    // MARK: - Border/background (pt.css `.cert`/`.cert-in`)

    private var innerBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color(hex: 0x8A6E3A, alpha: 0.4), lineWidth: 1)
            .padding(4)
    }

    private var outerBorder: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(PT.gold, lineWidth: 1.5)
    }

    private var certBackground: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xF6EEDD), Color(hex: 0xEDE2C8)], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Single-price block
//
// A "KICKER / price / footnote" block for a one-price certificate context
// (also handy for confirmation states). All strings caller-supplied.

struct CertificatePriceBlock: View {
    let kicker: String
    let price: String
    var footnote: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(kicker.uppercased())
                .ptMonoLabel(11, tracking: 1.8)
                .foregroundStyle(PT.onPaper3)
            Text(price)
                .font(PTFont.serif(32, weight: 600))
                .foregroundStyle(PT.onPaper)
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11.5))
                    .foregroundStyle(PT.onPaper3)
            }
        }
    }
}

extension CertificateView where PriceSlot == CertificatePriceBlock {
    init(
        kicker: String = "Certificate of membership",
        title: String = "PaperTrail Plus",
        tagline: String,
        sealCaption: String = "PLUS ·\nMEMBER\n· EST 2026",
        benefits: [String],
        priceKicker: String,
        price: String,
        priceFootnote: String? = nil
    ) {
        self.init(kicker: kicker, title: title, tagline: tagline, sealCaption: sealCaption, benefits: benefits) {
            CertificatePriceBlock(kicker: priceKicker, price: price, footnote: priceFootnote)
        }
    }
}

// MARK: - PlanPickerRow (spec v2.1)
//
// A selectable plan row for the certificate's price slot — on-paper styling.
// Selection feedback: the border tint + an inset ring snap in over 150ms
// ease-out. Both strokes are ALWAYS in the view tree (only color/opacity
// change), so selecting never shifts layout. Wave D composes two of these
// (Annual default with ≈/month math, Monthly) above one `PlanFinePrint`.

struct PlanPickerRow: View {
    /// e.g. "Annual"
    let title: String
    /// e.g. "S$39.98/yr"
    let price: String
    /// Optional second line, e.g. "≈ S$3.33/mo" — the annual row's math.
    var detail: String? = nil
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PT.onPaper)
                    if let detail {
                        Text(detail)
                            .font(PTFont.mono(10))
                            .foregroundStyle(PT.onPaper3)
                    }
                }
                Spacer(minLength: 8)
                Text(price)
                    .font(PTFont.mono(12, medium: true))
                    .foregroundStyle(PT.onPaper)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            // Outer border: constant width, tint snaps gold on selection.
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isSelected ? PT.gold : Color(hex: 0x8A6E3A, alpha: 0.35), lineWidth: 1.5)
            )
            // Inset ring: always present, fades in on selection — no layout shift.
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(PT.goldDeep, lineWidth: 1)
                    .padding(3)
                    .opacity(isSelected ? 0.55 : 0)
            )
            .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The shared fine-print line under a plan picker. Crossfades (180ms) when
/// the text changes with the selection. Layout stability: the frame reserves
/// two lines (`minHeight`) so single/double-line copy variants don't shift
/// the certificate; keep copy within two lines.
/// v2.1 pattern: "First 2 weeks free · then <price>. We'll remind you before
/// every renewal. Cancel keeps everything."
struct PlanFinePrint: View {
    let text: String

    var body: some View {
        ZStack {
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(PT.onPaper3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .id(text)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: text)
    }
}

#Preview("CertificateView — plan picker") {
    struct Demo: View {
        @State private var annual = true
        var body: some View {
            ScrollView {
                CertificateView(
                    tagline: "Renewed yearly, like a library card.",
                    benefits: [
                        "Household sharing, unlimited members",
                        "Whole-home insurance report",
                        "Warranty Digest Pro",
                        "Every future Plus feature — included"
                    ]
                ) {
                    VStack(spacing: 8) {
                        PlanPickerRow(title: "Annual", price: "S$39.98/yr", detail: "≈ S$3.33/mo",
                                      isSelected: annual) { annual = true }
                        PlanPickerRow(title: "Monthly", price: "S$5.98/mo",
                                      isSelected: !annual) { annual = false }
                        PlanFinePrint(text: "First 2 weeks free · then \(annual ? "S$39.98/yr" : "S$5.98/mo"). We'll remind you before every renewal. Cancel keeps everything.")
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: 262)
                }
                .padding(24)
            }
            .ptScreen()
        }
    }
    return Demo()
}

#Preview("CertificateView — single price block") {
    ScrollView {
        CertificateView(
            tagline: "Renewed yearly, like a library card.",
            benefits: [
                "Household sharing, unlimited members",
                "Whole-home insurance report",
                "Warranty Digest Pro"
            ],
            priceKicker: "Annual membership",
            price: "S$39.98/yr",
            priceFootnote: "First 2 weeks free. Cancel keeps everything."
        )
        .padding(24)
    }
    .ptScreen()
}
