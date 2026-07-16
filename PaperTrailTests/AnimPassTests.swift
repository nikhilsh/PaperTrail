import Testing
import Foundation
@testable import PaperTrail

/// Pure logic tests for the v3 `animPassV3` motion pass (docs/design-v3/
/// V3_BRIEF.md §9): `RingFirstVisitPerDay`'s predicate (#10) and
/// `ClaimAssemblyChoreography`'s stagger math (#5). Everything else in
/// `AnimPass.swift` is view code (transitions, curves, a `PreferenceKey`)
/// with no pure logic worth a unit test beyond what these two cover.
struct AnimPassTests {

    // MARK: - #10 Ring first-visit-per-day

    private let now = Date(timeIntervalSince1970: 1_752_000_000) // fixed anchor, arbitrary

    @Test func neverAnimatedBeforeShouldAnimate() {
        #expect(RingFirstVisitPerDay.shouldAnimate(lastAnimatedDate: nil, now: now))
    }

    @Test func sameCalendarDayShouldNotAnimateAgain() {
        let earlierToday = now.addingTimeInterval(-3600) // 1h earlier, same day
        #expect(!RingFirstVisitPerDay.shouldAnimate(lastAnimatedDate: earlierToday, now: now))
    }

    @Test func exactSameInstantShouldNotAnimateAgain() {
        #expect(!RingFirstVisitPerDay.shouldAnimate(lastAnimatedDate: now, now: now))
    }

    @Test func nextCalendarDayShouldAnimateAgain() {
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        #expect(RingFirstVisitPerDay.shouldAnimate(lastAnimatedDate: nextDay, now: now))
    }

    @Test func justAfterMidnightCountsAsANewDay() {
        let calendar = Calendar.current
        let lastNight = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now)!
        let justAfterMidnight = calendar.date(byAdding: .minute, value: 2, to: lastNight)! // rolls into the next day
        #expect(RingFirstVisitPerDay.shouldAnimate(lastAnimatedDate: lastNight, now: justAfterMidnight))
    }

    @Test func markAnimatedThenReadRoundTrips() {
        let suiteName = "AnimPassTests.markAnimatedThenReadRoundTrips"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        #expect(RingFirstVisitPerDay.lastAnimatedDate(for: "record-1", defaults: suite) == nil)
        RingFirstVisitPerDay.markAnimated(for: "record-1", now: now, defaults: suite)
        #expect(RingFirstVisitPerDay.lastAnimatedDate(for: "record-1", defaults: suite) == now)
        // A different key is untouched.
        #expect(RingFirstVisitPerDay.lastAnimatedDate(for: "record-2", defaults: suite) == nil)
    }

    // MARK: - #5 Claim packet assembly stagger

    @Test func thumbDelayStartsAtZeroAndStepsBySixtyMilliseconds() {
        #expect(ClaimAssemblyChoreography.thumbDelay(index: 0) == 0)
        #expect(ClaimAssemblyChoreography.thumbDelay(index: 1) == 0.06)
        #expect(ClaimAssemblyChoreography.thumbDelay(index: 2) == 0.12)
    }

    @Test func ruleDelayIsImmediateWithNoThumbnails() {
        #expect(ClaimAssemblyChoreography.ruleDelay(thumbCount: 0) == 0)
    }

    @Test func ruleDelayFollowsTheLastThumbnailsEntrance() {
        // Rule draws only after the LAST thumbnail's own entrance has had
        // time to finish, not merely start.
        let lastThumb = ClaimAssemblyChoreography.thumbDelay(index: 2)
        #expect(ClaimAssemblyChoreography.ruleDelay(thumbCount: 3) > lastThumb)
    }

    @Test func armDelayFollowsTheRuleDraw() {
        for count in 0...3 {
            #expect(ClaimAssemblyChoreography.armDelay(thumbCount: count) > ClaimAssemblyChoreography.ruleDelay(thumbCount: count))
        }
    }

    @Test func moreThumbnailsPushEverythingLater() {
        #expect(ClaimAssemblyChoreography.ruleDelay(thumbCount: 3) > ClaimAssemblyChoreography.ruleDelay(thumbCount: 1))
        #expect(ClaimAssemblyChoreography.armDelay(thumbCount: 3) > ClaimAssemblyChoreography.armDelay(thumbCount: 1))
    }
}
