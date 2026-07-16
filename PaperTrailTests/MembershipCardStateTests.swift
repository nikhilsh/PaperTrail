import Testing
import Foundation
@testable import PaperTrail

/// Pure logic tests for the gold member card's state derivation — Wave D
/// (docs/design-v2/V2_BRIEF.md §3 "Post-purchase state" / P3): plan-term
/// mapping from a transaction's productID (`PTMembershipTerm.from`) and
/// lapse-state precedence (`PlusEntitlements.isLapsed`). No StoreKit/UIKit
/// involved — both are free functions over plain values.
struct MembershipCardStateTests {

    // MARK: - PTMembershipTerm.from (plan-term mapping)

    private let lifetimeID = "plus.lifetime"
    private let monthlyID = "plus.monthly"
    private let yearlyID = "plus.yearly"

    @Test func lifetimeProductMapsToLifetime() {
        let term = PTMembershipTerm.from(
            productID: lifetimeID,
            isIntroductoryOffer: false,
            renewalDateText: "12 Aug 2027",
            lifetimeProductID: lifetimeID,
            monthlyProductID: monthlyID
        )
        #expect(term == .lifetime)
    }

    @Test func lifetimeTakesPrecedenceOverIntroductoryOffer() {
        // Defensive: a lifetime SKU should never read as a trial, even if
        // some upstream field claimed it was an introductory offer.
        let term = PTMembershipTerm.from(
            productID: lifetimeID,
            isIntroductoryOffer: true,
            renewalDateText: "—",
            lifetimeProductID: lifetimeID,
            monthlyProductID: monthlyID
        )
        #expect(term == .lifetime)
    }

    @Test func introductoryOfferMapsToTrial() {
        let term = PTMembershipTerm.from(
            productID: yearlyID,
            isIntroductoryOffer: true,
            renewalDateText: "30 Jul 2026",
            lifetimeProductID: lifetimeID,
            monthlyProductID: monthlyID
        )
        #expect(term == .trial(billsOn: "30 Jul 2026"))
    }

    @Test func monthlyProductMapsToMonthly() {
        let term = PTMembershipTerm.from(
            productID: monthlyID,
            isIntroductoryOffer: false,
            renewalDateText: "1 Sep 2026",
            lifetimeProductID: lifetimeID,
            monthlyProductID: monthlyID,
            monthlyDayText: "the 1st"
        )
        #expect(term == .monthly(renewsOn: "1 Sep 2026", dayText: "the 1st"))
    }

    @Test func monthlyDayTextDefaultsToEmptyWhenOmitted() {
        // Callers that already know the plan isn't monthly shouldn't have to
        // bother computing a day-ordinal string that'll never be used.
        let term = PTMembershipTerm.from(
            productID: monthlyID,
            isIntroductoryOffer: false,
            renewalDateText: "1 Sep 2026",
            lifetimeProductID: lifetimeID,
            monthlyProductID: monthlyID
        )
        #expect(term == .monthly(renewsOn: "1 Sep 2026", dayText: ""))
    }

    @Test func yearlyProductMapsToAnnual() {
        let term = PTMembershipTerm.from(
            productID: yearlyID,
            isIntroductoryOffer: false,
            renewalDateText: "12 Aug 2027",
            lifetimeProductID: lifetimeID,
            monthlyProductID: monthlyID
        )
        #expect(term == .annual(renewsOn: "12 Aug 2027"))
    }

    @Test func lifetimeStatusTextAndSuffix() {
        #expect(PTMembershipTerm.lifetime.statusText == "NEVER EXPIRES")
        #expect(PTMembershipTerm.lifetime.memberLineSuffix == "LIFETIME")
    }

    @Test func trialStatusTextReadsBillsOn() {
        #expect(PTMembershipTerm.trial(billsOn: "30 JUL 2026").statusText == "TRIAL · BILLS 30 JUL 2026")
    }

    // MARK: - PlusEntitlements.isLapsed (lapse-state precedence)

    @Test func neverMemberIsNeverLapsed() {
        #expect(PlusEntitlements.isLapsed(wasEverMember: false, hasPlus: false) == false)
        #expect(PlusEntitlements.isLapsed(wasEverMember: false, hasPlus: true) == false)
    }

    @Test func currentMemberIsNeverLapsedRegardlessOfHistory() {
        #expect(PlusEntitlements.isLapsed(wasEverMember: true, hasPlus: true) == false)
    }

    @Test func formerMemberWithoutCurrentPlusIsLapsed() {
        #expect(PlusEntitlements.isLapsed(wasEverMember: true, hasPlus: false) == true)
    }

    // MARK: - preferredMembership (§5: term pick order)

    private struct FakeEntitlement { let id: String; let expirationDate: Date? }

    @Test func activeSubscriptionBeatsLegacyLifetime() {
        // A legacy lifetime purchase and a live subscription can both be
        // simultaneously "current" — the active subscription must win.
        let lifetime = FakeEntitlement(id: "lifetime", expirationDate: nil)
        let subscription = FakeEntitlement(id: "subscription", expirationDate: Date(timeIntervalSince1970: 2_000_000_000))
        let winner = PlusEntitlements.preferredMembership(among: [lifetime, subscription]) { $0.expirationDate }
        #expect(winner?.id == "subscription")

        // Order in the input shouldn't matter.
        let winnerReversed = PlusEntitlements.preferredMembership(among: [subscription, lifetime]) { $0.expirationDate }
        #expect(winnerReversed?.id == "subscription")
    }

    @Test func laterExpirationWinsAmongSubscriptions() {
        let sooner = FakeEntitlement(id: "sooner", expirationDate: Date(timeIntervalSince1970: 1_000_000_000))
        let later = FakeEntitlement(id: "later", expirationDate: Date(timeIntervalSince1970: 2_000_000_000))
        let winner = PlusEntitlements.preferredMembership(among: [sooner, later]) { $0.expirationDate }
        #expect(winner?.id == "later")
    }

    @Test func singleCandidateWinsTrivially() {
        let only = FakeEntitlement(id: "only", expirationDate: nil)
        let winner = PlusEntitlements.preferredMembership(among: [only]) { $0.expirationDate }
        #expect(winner?.id == "only")
    }

    @Test func emptyCandidatesReturnsNil() {
        let winner = PlusEntitlements.preferredMembership(among: [FakeEntitlement]()) { $0.expirationDate }
        #expect(winner == nil)
    }

    // MARK: - ordinalDayText (§3b: monthly footer's day-of-month)

    private let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }

    @Test func ordinalDaySuffixes() {
        #expect(PTMembershipTerm.ordinalDayText(for: date("2026-09-01"), calendar: utcCalendar) == "the 1st")
        #expect(PTMembershipTerm.ordinalDayText(for: date("2026-09-02"), calendar: utcCalendar) == "the 2nd")
        #expect(PTMembershipTerm.ordinalDayText(for: date("2026-09-03"), calendar: utcCalendar) == "the 3rd")
        #expect(PTMembershipTerm.ordinalDayText(for: date("2026-09-04"), calendar: utcCalendar) == "the 4th")
        #expect(PTMembershipTerm.ordinalDayText(for: date("2026-09-21"), calendar: utcCalendar) == "the 21st")
    }

    @Test func ordinalDayTeensAreAlwaysTh() {
        // 11th/12th/13th are the classic exceptions to the 1/2/3 → st/nd/rd rule.
        #expect(PTMembershipTerm.ordinalDayText(for: date("2026-09-11"), calendar: utcCalendar) == "the 11th")
        #expect(PTMembershipTerm.ordinalDayText(for: date("2026-09-12"), calendar: utcCalendar) == "the 12th")
        #expect(PTMembershipTerm.ordinalDayText(for: date("2026-09-13"), calendar: utcCalendar) == "the 13th")
    }
}
