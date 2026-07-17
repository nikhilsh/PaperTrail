import Testing
import Foundation
@testable import PaperTrail

/// Pure copy-logic tests for `PaywallCopy` (§2: trial-copy honesty) — the
/// plan×eligible×hasIntro matrix that decides the paywall's CTA label and
/// fine print for the selected plan. No StoreKit `Product` involved:
/// `offersTrial` already folds together "has an intro offer" and "is
/// eligible for it", so these tests only need to vary that single boolean
/// plus plan/price.
struct PaywallCopyTests {

    // MARK: - ctaTitle

    @Test func ctaOffersTrialShowsStartFree() {
        #expect(PaywallCopy.ctaTitle(plan: .annual, offersTrial: true, priceText: "S$39.98/yr") == "Start 2 weeks free")
    }

    @Test func ctaOffersTrialIgnoresMissingPrice() {
        // Trial copy never needs to quote a price up front.
        #expect(PaywallCopy.ctaTitle(plan: .annual, offersTrial: true, priceText: nil) == "Start 2 weeks free")
    }

    @Test func ctaNoTrialShowsSubscribeWithPrice() {
        #expect(PaywallCopy.ctaTitle(plan: .annual, offersTrial: false, priceText: "S$39.98/yr") == "Subscribe — S$39.98/yr")
        #expect(PaywallCopy.ctaTitle(plan: .monthly, offersTrial: false, priceText: "S$5.98/mo") == "Subscribe — S$5.98/mo")
    }

    @Test func ctaNoTrialNoPriceYetShowsBareSubscribe() {
        #expect(PaywallCopy.ctaTitle(plan: .monthly, offersTrial: false, priceText: nil) == "Subscribe")
    }

    @Test func ctaLifetimeBuysItNeverSubscribes() {
        // A non-consumable is a purchase, not a subscription — and it can
        // never carry a trial, whatever it's handed.
        #expect(PaywallCopy.ctaTitle(plan: .lifetime, offersTrial: false, priceText: "S$68.98") == "Buy once — S$68.98")
        #expect(PaywallCopy.ctaTitle(plan: .lifetime, offersTrial: true, priceText: "S$68.98") == "Buy once — S$68.98")
        #expect(PaywallCopy.ctaTitle(plan: .lifetime, offersTrial: false, priceText: nil) == "Buy once")
    }

    // MARK: - finePrint

    @Test func finePrintTrialEligibleYearly() {
        let text = PaywallCopy.finePrint(plan: .annual, offersTrial: true, priceText: "S$39.98/yr")
        #expect(text == "First 2 weeks free · then S$39.98/yr. We'll remind you before every renewal. Cancel keeps everything.")
    }

    @Test func finePrintPaidYearlyKeepsRenewalPromise() {
        // Not eligible (already used the trial) or no intro offer at all —
        // still annual, so the renewal-reminder promise is real and stays.
        let text = PaywallCopy.finePrint(plan: .annual, offersTrial: false, priceText: "S$39.98/yr")
        #expect(text == "S$39.98/yr. We'll remind you before every renewal. Cancel keeps everything.")
    }

    @Test func finePrintMonthlyDropsRenewalPromise() {
        // Monthly never has a trial in ASC and never gets a scheduled
        // renewal reminder (`PlusEntitlements.updateRenewalReminder` is
        // annual-only) — the fine print must not promise one.
        let text = PaywallCopy.finePrint(plan: .monthly, offersTrial: false, priceText: "S$5.98/mo")
        #expect(text == "S$5.98/mo. Cancel keeps everything.")
    }

    @Test func finePrintMonthlyNeverShowsTrialCopyEvenIfOffersTrialWereTrue() {
        // Defensive: PaywallView never actually passes offersTrial: true for
        // monthly (ASC has no intro offer on it), but if it somehow did,
        // finePrint still has to obey the flag it's given — the "monthly
        // never promises a trial" guarantee lives in PaywallView's
        // `offersTrial(_:)`, not here. This documents that boundary.
        let text = PaywallCopy.finePrint(plan: .monthly, offersTrial: true, priceText: "S$5.98/mo")
        #expect(text.hasPrefix("First 2 weeks free"))
    }

    @Test func finePrintLifetimeStatesTheNoRenewalFact() {
        let text = PaywallCopy.finePrint(plan: .lifetime, offersTrial: false, priceText: "S$68.98")
        #expect(text == "S$68.98 once. Nothing renews. Yours forever.")
        // Even a bogus trial flag can't make a non-consumable promise one.
        #expect(PaywallCopy.finePrint(plan: .lifetime, offersTrial: true, priceText: "S$68.98") == text)
    }

    @Test func finePrintMissingPriceFallsBackToEmDash() {
        let text = PaywallCopy.finePrint(plan: .annual, offersTrial: false, priceText: nil)
        #expect(text == "—. We'll remind you before every renewal. Cancel keeps everything.")
    }
}
