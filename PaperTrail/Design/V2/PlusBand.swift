import SwiftUI

// MARK: - PlusBand (docs/design-v2/DESIGN_LANGUAGE.md §5 S1, pt.css `.plusband`)
//
// A foil band designed to fuse to a `PaperCardV2`'s bottom edge — identity +
// upgrade as one object. ANIMATION_SPEC §2: a once-per-install sheen sweep
// (70pt highlight, skew -18°, 1.4s, 0.8s delay) — persisted via UserDefaults
// so it never replays on later visits.
//
// SPEC v2.1 (subscription-only): title/tagline and the trailing price
// string are caller-supplied — Wave D passes live StoreKit copy. House copy:
// "PaperTrail Plus / Annual membership · first 2 weeks free / <price>/YR ›".

struct PlusBand: View {
    var title: String = "PaperTrail Plus"
    var tagline: String
    /// Trailing price/label text, e.g. "S$39.98/YR". The component appends
    /// the "›" affordance itself — that's chrome, not copy.
    var priceText: String
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSheen = false
    @State private var sheenProgress: CGFloat = 0

    /// Persists across installs of this key's UserDefaults suite (i.e. once
    /// per app install, per the spec) — not per-session, per-screen-visit.
    private static let sheenShownKey = "pt.v2.plusBandSheenShownOnce"

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(tagline)
                        .font(.system(size: 11))
                        .opacity(0.75)
                }
                Spacer(minLength: 8)
                Text("\(priceText) ›")
                    .font(PTFont.mono(11, medium: true))
                    .tracking(1.1)
            }
            .foregroundStyle(PT.inkStamp)
            .padding(.horizontal, 20)
            .padding(.top, 13)
            .padding(.bottom, 15)
            .background(bandBackground)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
        }
        .buttonStyle(.plain)
        .onAppear(perform: startSheenIfNeeded)
    }

    private var bandBackground: some View {
        ZStack {
            PT.foilGradient
            if showSheen {
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 70, height: geo.size.height * 1.6)
                        .rotationEffect(.degrees(-18))
                        .offset(x: -90 + sheenProgress * (w + 160))
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func startSheenIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.sheenShownKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.sheenShownKey)
        // Reduce Motion: skip the sheen sweep entirely (ANIMATION_SPEC "Don'ts").
        guard !reduceMotion else { return }
        showSheen = true
        sheenProgress = 0
        withAnimation(.easeOut(duration: 1.4).delay(0.8)) {
            sheenProgress = 1
        }
    }
}

#Preview("PlusBand") {
    VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your records").font(PTFont.serif(24, weight: 600))
            Text("Backed up 13 seconds ago").font(.system(size: 13)).foregroundStyle(PT.onPaper2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        PlusBand(tagline: "Annual membership · first 2 weeks free", priceText: "S$39.98/YR") {}
    }
    .background(PT.paperFill)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .padding(24)
    .ptScreen()
}
