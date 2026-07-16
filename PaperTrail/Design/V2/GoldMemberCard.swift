import SwiftUI

// MARK: - GoldMemberCard (docs/design-v2/DESIGN_LANGUAGE.md §4/§5 P3, pt.css `.goldcard`)
//
// The post-purchase "library card, re-struck in gold" — permanent visible
// Plus status in Settings. Entrance is a card being turned over: rotateY
// 90°→0 + scale .96→1 + fade, 550ms archiveEase (ANIMATION_SPEC §4).
//
// SPEC UPDATE (subscriptions stay alongside lifetime): the membership-term
// line is parameterized by `PTMembershipTerm` rather than hardcoded
// "LIFETIME · NEVER EXPIRES" — a subscriber sees "PLUS · RENEWS <date>".

/// The two membership shapes the card can represent. `renewsOn` is a
/// pre-formatted, display-ready date string (formatting is the caller's
/// concern — this view has no opinion on date style/locale).
enum PTMembershipTerm {
    case lifetime
    case subscriber(renewsOn: String)

    /// The `MEMBER Nº NNNNNN · <term>` suffix.
    var memberLineSuffix: String {
        switch self {
        case .lifetime: "LIFETIME"
        case .subscriber: "PLUS"
        }
    }

    /// The trailing stats-row chip: "NEVER EXPIRES" or "RENEWS <date>".
    var statusText: String {
        switch self {
        case .lifetime: "NEVER EXPIRES"
        case .subscriber(let renewsOn): "RENEWS \(renewsOn.uppercased())"
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

#Preview("GoldMemberCard — lifetime") {
    GoldMemberCard(
        name: "Your library",
        memberNumber: memberNumber(fromTransactionID: "2000000123456789"),
        term: .lifetime,
        itemCount: 5,
        totalValue: "$3,116"
    )
    .padding(24)
    .ptScreen()
}

#Preview("GoldMemberCard — subscriber") {
    GoldMemberCard(
        name: "Your library",
        memberNumber: memberNumber(fromTransactionID: "2000000987654321"),
        term: .subscriber(renewsOn: "12 Aug 2027"),
        itemCount: 5,
        totalValue: "$3,116"
    )
    .padding(24)
    .ptScreen()
}
