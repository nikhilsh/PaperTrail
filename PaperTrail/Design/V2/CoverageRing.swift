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
    /// Suffix after the center count, e.g. "mo" (default) or "d" when the
    /// caller is displaying days instead of months (V2_BRIEF §2: "days when
    /// <2 months" left). Purely a label — `totalMonths`/`monthsRemaining` are
    /// unitless counts the caller is free to pass in whatever unit this
    /// suffix names.
    var unitSuffix: String = "mo"
    /// Center caption under the count, e.g. "REMAINING" (default, v2) or
    /// "longest line" (v3 `multiCoverage` — V3_BRIEF §2, mock V3-2) when the
    /// ring is showing the longest of several coverage lines rather than a
    /// single warranty span. Purely a label swap; the count/arc math is
    /// unaffected either way.
    var caption: String = "REMAINING"
    var diameter: CGFloat = 150
    var lineWidth: CGFloat = 9
    /// v3 animPassV3 §9 #10 "Ring first-visit-per-day": when set (and the
    /// flag is on), the arc-sweep/count-up only plays the first time this
    /// key is seen on a given calendar day — every later visit that day
    /// jumps straight to the static final fill. `nil` (the default) keeps
    /// v2's "every visit" behavior unconditionally, flag or no flag — a
    /// caller has to opt a specific ring into the once-per-day gate by
    /// passing its identity.
    var identityKey: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedFraction: CGFloat = 0
    @State private var displayedMonths: Int = 0
    /// The in-flight count-up, so a rapid `monthsRemaining` change (or the
    /// view disappearing) cancels the previous run instead of leaving it to
    /// race the new one and stomp `displayedMonths` out of order.
    @State private var countUpTask: Task<Void, Never>?

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
                Text("\(displayedMonths) \(unitSuffix)")
                    .font(PTFont.serif(38, weight: 600))
                    .foregroundStyle(PT.onPaper)
                Text(caption)
                    .ptMonoLabel(9, tracking: 2)
                    .foregroundStyle(PT.onPaper3)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear(perform: animate)
        .onChange(of: monthsRemaining) { _, _ in animate() }
        .onDisappear { countUpTask?.cancel() }
    }

    private func animate() {
        countUpTask?.cancel()
        if reduceMotion {
            animatedFraction = targetFraction
            displayedMonths = clampedRemaining
            return
        }
        // v3 animPassV3 §9 #10: static fill after the first visit today for
        // whichever `identityKey` the caller opted in. Off-flag (or no key
        // passed at all), this block never runs and the ring animates on
        // every visit exactly as in v2.
        if AnimPass.isOn, let identityKey {
            let last = RingFirstVisitPerDay.lastAnimatedDate(for: identityKey)
            if RingFirstVisitPerDay.shouldAnimate(lastAnimatedDate: last) {
                RingFirstVisitPerDay.markAnimated(for: identityKey)
            } else {
                animatedFraction = targetFraction
                displayedMonths = clampedRemaining
                return
            }
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
    /// long past it. A single cancellable `Task` sleeping in a loop, rather
    /// than a batch of `DispatchQueue.asyncAfter` callbacks — those can't be
    /// cancelled, so a value change mid-count used to leave the old run's
    /// callbacks free to fire later and stomp the new one's `displayedMonths`.
    private func countUp() {
        guard clampedRemaining > 0 else { return }
        let arcDuration = 0.65 // 0.9s sweep minus its own 0.25s delay
        let remaining = clampedRemaining
        let stepDuration = min(0.07, arcDuration / Double(remaining))
        countUpTask = Task {
            try? await Task.sleep(for: .seconds(0.25))
            guard !Task.isCancelled else { return }
            for step in 0...remaining {
                guard !Task.isCancelled else { return }
                displayedMonths = step
                guard step < remaining else { break }
                try? await Task.sleep(for: .seconds(stepDuration))
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
