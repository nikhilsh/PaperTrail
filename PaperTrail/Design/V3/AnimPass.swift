import SwiftUI

// MARK: - AnimPass (docs/design-v3/V3_BRIEF.md §9 `animPassV3`, `PaperTrail v3
// Ideas.html` Section D "Animation map")
//
// Central helpers for the ten v3 motion moments. Every call site funnels
// through here for its duration constant + curve + Reduce Motion
// resolution, so the two rules that apply to all ten
// ("flag off = v2 motion EXACTLY", "Reduce Motion → 200ms crossfade, no
// transforms") live in one place instead of being re-derived at each touch
// point. Individual animations still live where they're rendered (LibraryView,
// ServiceLedgerTimelineView, RecordDetailView, ClaimPacketView,
// PassItOnBuilderView, SettingsView, WarrantyView's DigestCard, CoverageRing)
// — this file has no view code of its own beyond the two small reusable
// pieces (#7's ribbon, #4's ellipsis) that don't have a single natural home.

enum AnimPass {
    /// Single flag check every one of the ten animations gates on. A thin
    /// wrapper (not just `FeatureFlags.isOn(.animPassV3)` inline everywhere)
    /// so call sites read as "is the anim pass on" rather than repeating the
    /// enum case.
    static var isOn: Bool { FeatureFlags.isOn(.animPassV3) }

    /// Resolves `curve` normally, or ANIMATION_SPEC's Reduce Motion escape
    /// hatch (flat 200ms crossfade) when `reduceMotion` is set — every
    /// animation in this pass shares this one rule, so it's a pass-through
    /// to `PTMotion.reduced` rather than a second implementation.
    static func animation(_ curve: Animation, reduceMotion: Bool) -> Animation {
        PTMotion.reduced(curve, reduceMotion: reduceMotion)
    }

    /// Named durations from the Ideas.html Section D map, kept as constants
    /// so a call site and the design doc agree on "what 380ms means" at a
    /// glance instead of a bare magic number.
    enum Duration {
        static let receiptPrint: Double = 0.45
        static let shelving: Double = 0.38
        static let ledgerStamp: Double = 0.32
        /// The dossier-open ellipsis hold before the recall row resolves —
        /// ~600ms of the row's overall ~800ms per Ideas.html.
        static let recallEllipsisHold: Double = 0.6
        /// The resolve transition itself, after the ellipsis hold.
        static let recallResolve: Double = 0.2
        static let claimAssembly: Double = 1.1
        static let claimStagger: Double = 0.06
        static let handover: Double = 0.5
        static let odometer: Double = 0.4
        static let digestCurl: Double = 0.55
    }
}

// MARK: - #10 Ring first-visit-per-day

/// Persists the last calendar day the Coverage Ring played its arc-sweep +
/// count-up for a given identity (a record id, or any caller-chosen key).
/// Split into a pure predicate (`shouldAnimate`, unit-tested with injected
/// dates/calendars) and a thin `UserDefaults`-backed read/write pair —
/// `CoverageRing` itself only calls the read/write side.
enum RingFirstVisitPerDay {
    private static let keyPrefix = "animPassV3.ringLastAnimated."

    /// True when `lastAnimatedDate` (nil = never animated) falls on a
    /// different calendar day than `now` — i.e. this is the first visit
    /// today, and the ring should play its full sweep/count-up.
    static func shouldAnimate(lastAnimatedDate: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let lastAnimatedDate else { return true }
        return !calendar.isDate(lastAnimatedDate, inSameDayAs: now)
    }

    static func lastAnimatedDate(for key: String, defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: keyPrefix + key) as? Date
    }

    static func markAnimated(for key: String, now: Date = .now, defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: keyPrefix + key)
    }
}

// MARK: - #5 Claim packet assembly stagger

/// Pure stagger math for the claim-packet assembly (§9 / Ideas.html D):
/// thumbnails fly in staggered 60ms apart, then the gold rule draws, then
/// SHARE arms. `ClaimPacketView` reads these delays rather than hand-rolling
/// the sequence inline — also what `AnimPassTests` exercises directly,
/// without needing a live view.
enum ClaimAssemblyChoreography {
    /// Delay before thumbnail `index` (0-based) begins its own entrance.
    static func thumbDelay(index: Int) -> Double {
        Double(index) * AnimPass.Duration.claimStagger
    }

    /// Delay before the gold rule begins drawing — after the last
    /// thumbnail's own entrance animation has had time to finish, not just
    /// start. `thumbCount == 0` draws the rule immediately.
    static func ruleDelay(thumbCount: Int) -> Double {
        thumbCount == 0 ? 0 : thumbDelay(index: thumbCount - 1) + 0.22
    }

    /// Delay before SHARE arms — after the rule has finished drawing.
    static func armDelay(thumbCount: Int) -> Double {
        ruleDelay(thumbCount: thumbCount) + 0.28
    }
}

// MARK: - #4 Recall check ellipsis

/// The dossier-open "Watching…" row's 3-dot mono ellipsis (Ideas.html D:
/// "shows a 3-dot mono ellipsis for ~600ms then resolves"). Three dots
/// pulsing in sequence — bounded to the ~600ms hold the caller drives it
/// for (the row is swapped out for the resolved state right after), not an
/// idle/infinite loop left running.
struct RecallEllipsisView: View {
    /// One shared trigger; each dot's own `.animation(...repeatForever...)`
    /// reads it with a per-dot `.delay`, which is what actually produces the
    /// staggered pulse — flipping a single Bool once rather than
    /// hand-rolling a 3-phase state machine.
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { dot in
                Circle()
                    .fill(PT.txt3)
                    .frame(width: 3.5, height: 3.5)
                    .opacity(animating ? 1 : 0.25)
                    .animation(
                        // `repeatForever` here is bounded in practice: the
                        // parent row replaces this view entirely ~600ms
                        // after it appears (`RecordDetailView.recallRow`'s
                        // `.checking` hold), which tears the animation down
                        // with it — never left running once the row resolves.
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(dot) * 0.16),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - #7 Pull-to-refresh gold bookmark

/// Tracks `LibraryView`'s `ScrollView` content offset in its own named
/// coordinate space so the gold ribbon (below) can follow overscroll
/// 1:1 — gesture-driven, not animated per se; it just redraws every frame
/// SwiftUI reports a new offset, the same way the system's own refresh
/// spinner tracks pull distance.
struct LibraryScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Decorative overscroll indicator for LibraryView's pull-to-refresh
/// (Ideas.html D: "Overscroll pulls a gold ribbon bookmark down; release
/// snaps it back up as sync runs."). Ships as a DECORATIVE layer alongside
/// the system spinner rather than a full custom-refresh replacement — see
/// `LibraryView`'s doc comment on `.refreshable` for why: a from-scratch
/// custom refresh control fights `refreshable`'s own gesture recognizer,
/// and the honest version here is "the system spinner does the real work,
/// this ribbon just makes the pull feel like PaperTrail." Purely a function
/// of the live scroll offset the caller passes in — no animation curve of
/// its own, so there's nothing for Reduce Motion to disable beyond the
/// caller not showing it at all.
struct GoldBookmarkRibbon: View {
    /// Positive overscroll distance in points (0 = at rest / scrolled away).
    var pull: CGFloat

    private let maxPull: CGFloat = 90
    private var clamped: CGFloat { min(max(pull, 0), maxPull) }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PT.goldFoil)
                .frame(width: 13, height: max(0, clamped - 9))
            RibbonNotch()
                .fill(PT.gold)
                .frame(width: 13, height: 9)
        }
        .opacity(clamped > 8 ? min(1, (clamped - 8) / 24) : 0)
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The V-notch at a bookmark ribbon's loose end.
private struct RibbonNotch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Conditionally attaches `.refreshable` — SwiftUI modifiers are
    /// structural, so a plain `if enabled { self.refreshable {...} }`
    /// `@ViewBuilder` is the standard way to make one optional. Used by
    /// `LibraryView` so pull-to-refresh (part of `animPassV3` #7) only
    /// exists as a gesture at all when the flag is on — off-flag, the
    /// ScrollView has exactly zero new behavior, matching v2.
    @ViewBuilder
    func libraryRefreshable(enabled: Bool, action: @escaping () async -> Void) -> some View {
        if enabled {
            self.refreshable { await action() }
        } else {
            self
        }
    }
}
