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
            monthlyProductID: monthlyID
        )
        #expect(term == .monthly(renewsOn: "1 Sep 2026"))
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
}
