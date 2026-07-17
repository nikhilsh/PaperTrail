import SwiftUI

// MARK: - SoftAskSheet (docs/design-v2/V2_BRIEF.md §4 N1, pt.css `.sheet`/`.banner`)
//
// A paper sheet over the dimmed app: kicker, title, promise copy, an
// embedded rendered sample-notification banner, then "Yes, notify me" /
// "NOT NOW". ANIMATION_SPEC §6: the sample banner drops in (translateY
// −16→0 + fade, 400ms, 350ms delay after the sheet rises). Pure
// presentation — no `UNUserNotificationCenter` calls here; the real prompt
// and the dim/sheet-rise transition are wired at the call site (Wave E).

struct SoftAskSheet: View {
    /// The sample notification's title, e.g. "Samsung TV — 2 weeks left".
    let itemName: String
    /// The sample notification's body, e.g. "Warranty ends 3 Jun. Your proof
    /// is ready if you need it."
    let stakeText: String
    var timeLabel: String = "now"
    /// Copy parameters, defaulted to the original N1 first-save copy —
    /// `SoftAskCoordinator`'s call site never passes these, so its behavior
    /// stays byte-for-byte identical. `NotificationPermissionGate` passes
    /// per-`AskContext` copy (e.g. the monthly digest ask) through the same
    /// sheet rather than duplicating the whole paper-card scaffolding.
    var kicker: String = "BEFORE YOU PUT THIS AWAY"
    var title: String = "May we leave a note?"
    var bodyText: String = "One quiet heads-up before a warranty or return window closes. That's the only reason we'll ever knock. No marketing, ever."
    var onYes: () -> Void
    var onNotNow: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bannerIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kicker)
                .ptMonoLabel(10, tracking: 2.2)
                .foregroundStyle(PT.goldDeep)

            Text(title)
                .font(PTFont.serif(27, weight: 600))
                .foregroundStyle(PT.onPaper)
                .padding(.top, 8)

            Text(bodyText)
                .font(.system(size: 14))
                .foregroundStyle(PT.onPaper2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            sampleBanner
                .padding(.top, 16)
                .opacity(bannerIn ? 1 : 0)
                // Reduce Motion: pure crossfade, no translation.
                .offset(y: bannerIn || reduceMotion ? 0 : -16)
                .onAppear(perform: dropBannerIn)

            Button(action: onYes) {
                Text("Yes, notify me")
            }
            .buttonStyle(PTDarkButtonStyle(fullWidth: true))
            .padding(.top, 18)

            Button(action: onNotNow) {
                Text("NOT NOW")
                    .font(PTFont.mono(10.5, medium: true))
                    .tracking(1.4)
                    .foregroundStyle(PT.onPaper3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }

            Text("iOS will ask to confirm next.")
                .font(.system(size: 10.5))
                .foregroundStyle(PT.onPaper3)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
        .padding(22)
        .paperCard(goldFold: false)
    }

    // MARK: - Sample notification banner (pt.css `.banner`)

    private var sampleBanner: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [PT.inkRaised, PT.inkPanel], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(PT.gold.opacity(0.4), lineWidth: 0.5)
                    )
                Image(systemName: "seal.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(PT.gold)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(itemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(stakeText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Text(timeLabel)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(Color(hex: 0x14110D, alpha: 0.94), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.6), radius: 15, x: 0, y: 10)
    }

    private func dropBannerIn() {
        withAnimation(PTMotion.reduced(.easeOut(duration: 0.4).delay(0.35), reduceMotion: reduceMotion)) {
            bannerIn = true
        }
    }
}

#Preview("SoftAskSheet") {
    ZStack {
        PT.inkCanvas.ignoresSafeArea()
        SoftAskSheet(
            itemName: "Samsung TV — 2 weeks left",
            stakeText: "Warranty ends 3 Jun. Your proof is ready if you need it.",
            onYes: {},
            onNotNow: {}
        )
        .padding(14)
    }
}
