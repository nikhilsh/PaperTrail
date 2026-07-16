import SwiftUI

// MARK: - GoldMemberCard (docs/design-v2/DESIGN_LANGUAGE.md §4/§5 P3, pt.css `.goldcard`)
//
// The post-purchase "library card, re-struck in gold" — permanent visible
// Plus status in Settings. Entrance is a card being turned over: rotateY
// 90°→0 + scale .96→1 + fade, 550ms archiveEase (ANIMATION_SPEC §4).
//
// SPEC v2.1 (subscription-only; supersedes the brief's lifetime framing):
// membership terms are ANNUAL / MONTHLY (plus a TRIAL state), the status
// chip reads "RENEWS <date>" (or "TRIAL · BILLS <date>"), and the card
// carries a renewal-promise footer with a MANAGE › affordance (callback —
// the screen wires the App Store manage-subscriptions deep link in Wave D).
//
// Wave D note (lapse motion): when membership lapses, the gold card
// crossfades to the cream card over 600ms on the next Settings visit —
// that's a screen-level swap (`withAnimation(.easeInOut(duration: 0.6))`
// around the card switch), not something this component animates itself.
// The quiet lapsed-state upsell band is `LapsedRenewBand` below.

/// The membership shapes the card can represent. Date strings are
/// pre-formatted, display-ready (formatting is the caller's concern — this
/// view has no opinion on date style/locale).
///
/// `nonisolated`: pure value logic with no UI state — keeps it callable from
/// the test target, which (unlike the app target) doesn't default to
/// MainActor isolation. `Equatable` for tests (`MembershipCardStateTests`).
nonisolated enum PTMembershipTerm: Equatable {
    case annual(renewsOn: String)
    case monthly(renewsOn: String)
    /// Free-trial period: bills (rather than renews) on the given date.
    case trial(billsOn: String)
    /// Legacy one-time purchase (Wave D: no longer sold, but a past buyer
    /// must keep working forever — docs/design-v2/V2_BRIEF.md hard rules).
    case lifetime

    /// The `MEMBER Nº NNNNNN · <term>` suffix.
    var memberLineSuffix: String {
        switch self {
        case .annual: "ANNUAL"
        case .monthly: "MONTHLY"
        case .trial: "TRIAL"
        case .lifetime: "LIFETIME"
        }
    }

    /// The trailing stats-row chip: "RENEWS <date>" / "TRIAL · BILLS <date>"
    /// / "NEVER EXPIRES" (DESIGN_LANGUAGE.md §5, lifetime's fixed caption).
    var statusText: String {
        switch self {
        case .annual(let date), .monthly(let date): "RENEWS \(date.uppercased())"
        case .trial(let date): "TRIAL · BILLS \(date.uppercased())"
        case .lifetime: "NEVER EXPIRES"
        }
    }

    /// Maps a live entitlement transaction's fields to the term the gold
    /// card shows. Pure — callers pass pre-formatted `renewalDateText` and
    /// the relevant product IDs rather than a live `StoreKit.Transaction`,
    /// so this is testable without StoreKit (`MembershipCardStateTests`).
    /// Lifetime wins regardless of the other fields — a legacy purchase
    /// never reads as a trial or a term.
    nonisolated static func from(
        productID: String,
        isIntroductoryOffer: Bool,
        renewalDateText: String,
        lifetimeProductID: String,
        monthlyProductID: String
    ) -> PTMembershipTerm {
        if productID == lifetimeProductID {
            .lifetime
        } else if isIntroductoryOffer {
            .trial(billsOn: renewalDateText)
        } else if productID == monthlyProductID {
            .monthly(renewsOn: renewalDateText)
        } else {
            .annual(renewsOn: renewalDateText)
        }
    }
}

struct GoldMemberCard: View {
    let name: String
    /// Pass `memberNumber(fromTransactionID:)`'s output — already 6-digit,
    /// zero-padded.
    let memberNumber: String
    let term: PTMembershipTerm
    let itemCount: Int
    /// Pre-formatted currency string, e.g. "$3,116".
    let totalValue: String
    var synced: Bool = true
    /// Wires the MANAGE › affordance (App Store manage-subscriptions deep
    /// link, Wave D). Omit to hide the affordance.
    var onManage: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PAPERTRAIL · PLUS MEMBER")
                    .ptMonoLabel(9.5, tracking: 2.6)
                Spacer()
                Image(systemName: "sparkle")
                    .font(.system(size: 13))
            }

            Text(name)
                .font(PTFont.serif(27, weight: 600))
                .padding(.top, 20)

            Text("MEMBER Nº \(memberNumber) · \(term.memberLineSuffix)")
                .ptMonoLabel(11, tracking: 2)
                .opacity(0.75)
                .padding(.top, 4)

            HStack {
                Text(statsText)
                    .ptMonoLabel(9.5, tracking: 1.6)
                    .opacity(0.7)
                Spacer(minLength: 8)
                Text(term.statusText)
                    .ptMonoLabel(9.5, tracking: 1.6)
                    .opacity(0.7)
            }
            .padding(.top, 18)

            footer
                .padding(.top, 14)
        }
        .foregroundStyle(Color(hex: 0x241C0E))
        .padding(20)
        .background(memberGradient)
        .overlay(sheenOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: PT.gold.opacity(0.5), radius: 25, x: 0, y: 24)
        .rotation3DEffect(.degrees(appeared ? 0 : 90), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear(perform: strikeIn)
    }

    private var statsText: String {
        "\(itemCount) ITEM\(itemCount == 1 ? "" : "S") · \(totalValue)" + (synced ? " · SYNCED" : "")
    }

    /// Lifetime has nothing to "renew" — the honest-states rule means the
    /// footer shouldn't promise a knock that will never come.
    private var footerLine: String {
        switch term {
        case .lifetime: "Purchased once. Yours forever."
        default: "We'll knock 2 weeks before renewal."
        }
    }

    /// Renewal promise + MANAGE › — honest-states rule: the card itself says
    /// when and how it bills, and hands the user the exit.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(hex: 0x241C0E, alpha: 0.25))
                .frame(height: 1)
            HStack {
                Text(footerLine)
                    .font(.system(size: 11))
                    .opacity(0.75)
                Spacer(minLength: 8)
                if let onManage {
                    Button(action: onManage) {
                        Text("MANAGE ›")
                            .font(PTFont.mono(9.5, medium: true))
                            .tracking(1.6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
        }
    }

    /// pt.css `.goldcard`: `linear-gradient(120deg,#6E5628 0%,#A98A4E 30%,#E5CD90 50%,#A98A4E 70%,#6E5628 100%)`.
    private var memberGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x6E5628), location: 0.0),
                .init(color: Color(hex: 0xA98A4E), location: 0.30),
                .init(color: Color(hex: 0xE5CD90), location: 0.50),
                .init(color: Color(hex: 0xA98A4E), location: 0.70),
                .init(color: Color(hex: 0x6E5628), location: 1.0)
            ],
            // 120° in CSS ≈ down-and-right; topLeading/bottomTrailing is the
            // closest SwiftUI two-point approximation.
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// pt.css `.goldcard::before`: `radial-gradient(90% 70% at 70% 0%, rgba(255,255,255,.35), transparent 55%)`.
    private var sheenOverlay: some View {
        RadialGradient(colors: [.white.opacity(0.35), .clear],
                        center: UnitPoint(x: 0.7, y: 0), startRadius: 0, endRadius: 220)
            .allowsHitTesting(false)
    }

    private func strikeIn() {
        withAnimation(PTMotion.reduced(PTMotion.archiveEase(0.55), reduceMotion: reduceMotion)) {
            appeared = true
        }
    }
}

// MARK: - LapsedRenewBand (spec v2.1)
//
// The quiet lapsed-state companion: a cream band — deliberately NOT terra,
// no drama, no urgency — that Wave D shows in place of the Plus band when a
// membership has lapsed. "Renew your card — <price>".

struct LapsedRenewBand: View {
    /// Pre-formatted price, e.g. "S$39.98/yr".
    let priceText: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "creditcard")
                    .font(.system(size: 14))
                    .foregroundStyle(PT.goldDeep)
                Text("Renew your card")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(PT.onPaper)
                Spacer(minLength: 8)
                Text("\(priceText) ›")
                    .font(PTFont.mono(11, medium: true))
                    .tracking(1.1)
                    .foregroundStyle(PT.onPaper2)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(PT.paperFill)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
            .overlay(
                UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                    .stroke(PT.onPaperHair, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("GoldMemberCard — annual") {
    GoldMemberCard(
        name: "Your library",
        memberNumber: memberNumber(fromTransactionID: "2000000123456789"),
        term: .annual(renewsOn: "12 Aug 2027"),
        itemCount: 5,
        totalValue: "$3,116",
        onManage: {}
    )
    .padding(24)
    .ptScreen()
}

#Preview("GoldMemberCard — lifetime (legacy)") {
    GoldMemberCard(
        name: "Your library",
        memberNumber: memberNumber(fromTransactionID: "2000000112233445"),
        term: .lifetime,
        itemCount: 5,
        totalValue: "$3,116",
        onManage: nil
    )
    .padding(24)
    .ptScreen()
}

#Preview("GoldMemberCard — trial") {
    GoldMemberCard(
        name: "Your library",
        memberNumber: memberNumber(fromTransactionID: "2000000987654321"),
        term: .trial(billsOn: "30 Jul 2026"),
        itemCount: 5,
        totalValue: "$3,116",
        onManage: {}
    )
    .padding(24)
    .ptScreen()
}

#Preview("LapsedRenewBand") {
    LapsedRenewBand(priceText: "S$39.98/yr") {}
        .padding(24)
        .ptScreen()
}
