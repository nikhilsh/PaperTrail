import SwiftUI

// MARK: - CertificateView (docs/design-v2/V2_BRIEF.md §3 P1, pt.css `.cert`/`.cert-in`/`.seal`)
//
// The paywall's hero content: a cream "certificate of membership" with a
// double engraved border, a gold seal, benefit checks, and a price area.
// Content-only — the paywall screen (Wave D) wires in StoreKit, the buy
// button, and the PURCHASED-stamp/gold-strike sequence.
//
// SPEC UPDATE (subscriptions stay alongside lifetime): the price area is a
// generic slot (`PriceSlot`), not a hardcoded "ONE TIME / price / no
// subscription" block — Wave D may pass either the single-price convenience
// initializer below, or 2-3 selectable plan rows of its own. Nothing in this
// file hardcodes "No subscription. Nothing recurring, ever." — that copy is
// dead per the spec update. "Pay once. Keep it for life." is not hardcoded
// either; it's the caller-supplied `tagline`.

struct CertificateView<PriceSlot: View>: View {
    var kicker: String = "Certificate of membership"
    var title: String = "PaperTrail Plus"
    /// e.g. "Pay once. Keep it for life." for a lifetime-framed certificate —
    /// entirely caller-supplied, never hardcoded here.
    var tagline: String
    /// The seal's 3-line caption, e.g. "PLUS ·\nLIFETIME\n· EST 2026". Kept
    /// generic (default omits any plan assumption) since the certificate no
    /// longer implies lifetime-only.
    var sealCaption: String = "PLUS ·\n· EST 2026"
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

// MARK: - Single-price convenience (the "(a)" variant from the spec update)

/// A single "KICKER / price / footnote" block — the default look for a
/// one-price certificate. `kicker`/`price`/`footnote` are all caller strings;
/// none of the historical "ONE TIME" / "No subscription…" copy is baked in.
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
        sealCaption: String = "PLUS ·\n· EST 2026",
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

#Preview("CertificateView — single price") {
    ScrollView {
        CertificateView(
            tagline: "Pay once. Keep it for life.",
            sealCaption: "PLUS ·\nLIFETIME\n· EST 2026",
            benefits: [
                "Household sharing, unlimited members",
                "Whole-home insurance report",
                "Warranty Digest Pro",
                "Every future Plus feature — included"
            ],
            priceKicker: "One time",
            price: "S$69.98"
        )
        .padding(24)
    }
    .ptScreen()
}

#Preview("CertificateView — plan rows slot") {
    ScrollView {
        CertificateView(
            tagline: "One home. Every proof, in one place.",
            benefits: [
                "Household sharing, unlimited members",
                "Whole-home insurance report",
                "Warranty Digest Pro"
            ]
        ) {
            VStack(spacing: 8) {
                ForEach(["Monthly · S$5.98/mo", "Yearly · S$39.98/yr", "Lifetime · S$69.98 once"], id: \.self) { row in
                    Text(row)
                        .font(PTFont.mono(11.5, medium: true))
                        .foregroundStyle(PT.onPaper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(PT.onPaperHair, lineWidth: 1))
                }
            }
            .frame(maxWidth: 262)
        }
        .padding(24)
    }
    .ptScreen()
}
