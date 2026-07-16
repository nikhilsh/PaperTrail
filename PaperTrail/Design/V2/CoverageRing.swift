import SwiftUI

// MARK: - CoverageRing (docs/design-v2/V2_BRIEF.md §2 W2, pt.css `.gaugewrap`/`#ringArc`)
//
// The Coverage Passport's hero gauge: 9pt stroke, sage arc on a 12% track,
// serif center number. ANIMATION_SPEC §5: arc sweeps strokeDashoffset
// full→target over 900ms archiveEase with a 250ms delay after push; the
// center number counts 0→N at ~70ms/step, finishing with the arc. Runs on
// every visit (unlike the once-per-install rules elsewhere) — "it's the
// point of the page." Reduce Motion: crossfade to the final state, no
// count-up.

struct CoverageRing: View {
    /// Total months of coverage — the ring's 100%.
    let totalMonths: Int
    /// Months remaining right now — drives both the arc fraction and the
    /// center count-up.
    let monthsRemaining: Int
    var diameter: CGFloat = 150
    var lineWidth: CGFloat = 9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedFraction: CGFloat = 0
    @State private var displayedMonths: Int = 0

    private var clampedRemaining: Int { max(0, monthsRemaining) }

    private var targetFraction: CGFloat {
        guard totalMonths > 0 else { return 0 }
        return CGFloat(max(0, min(1, Double(clampedRemaining) / Double(totalMonths))))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(PT.onPaper.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animatedFraction)
                .stroke(PT.sage, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(displayedMonths) mo")
                    .font(PTFont.serif(38, weight: 600))
                    .foregroundStyle(PT.onPaper)
                Text("REMAINING")
                    .ptMonoLabel(9, tracking: 2)
                    .foregroundStyle(PT.onPaper3)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear(perform: animate)
        .onChange(of: monthsRemaining) { _, _ in animate() }
    }

    private func animate() {
        if reduceMotion {
            animatedFraction = targetFraction
            displayedMonths = clampedRemaining
            return
        }
        animatedFraction = 0
        displayedMonths = 0
        withAnimation(PTMotion.archiveEase(0.9).delay(0.25)) {
            animatedFraction = targetFraction
        }
        countUp()
    }

    /// ~70ms/step, but scaled down for large `monthsRemaining` so the count
    /// still finishes with the 900ms (250ms-delayed) arc rather than running
    /// long past it.
    private func countUp() {
        guard clampedRemaining > 0 else { return }
        let arcDuration = 0.65 // 0.9s sweep minus its own 0.25s delay
        let stepDuration = min(0.07, arcDuration / Double(clampedRemaining))
        for step in 0...clampedRemaining {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(step) * stepDuration) {
                displayedMonths = step
            }
        }
    }
}

#Preview("CoverageRing") {
    VStack(spacing: 30) {
        CoverageRing(totalMonths: 24, monthsRemaining: 10)
        CoverageRing(totalMonths: 24, monthsRemaining: 0)
    }
    .padding(30)
    .background(PT.paperFill)
}
