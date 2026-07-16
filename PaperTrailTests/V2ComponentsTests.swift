import Testing
import Foundation
@testable import PaperTrail

/// Pure-logic tests for the v2 design system (`PaperTrail/Design/V2/`):
/// `memberNumber(fromTransactionID:)` and the `PTMembershipTerm` copy
/// helpers. Everything else in that folder is SwiftUI view code with no
/// device-independent behavior to assert on.
///
/// Note: conditions are computed into plain `let` booleans before `#expect`
/// — interpolated comments / complex expressions inside the `#expect` macro
/// trip a "call can throw" error in its expansion on the CI toolchain.
struct V2ComponentsTests {

    // MARK: - memberNumber(fromTransactionID:)

    @Test func memberNumberIsDeterministic() {
        let first = memberNumber(fromTransactionID: "2000000123456789")
        let second = memberNumber(fromTransactionID: "2000000123456789")
        #expect(first == second)
    }

    @Test func memberNumberIsSixDigits() {
        let ids = ["2000000123456789", "", "a", "2000000987654321", "🎉", String(repeating: "x", count: 500)]
        for id in ids {
            let number = memberNumber(fromTransactionID: id)
            let isSixDigits = number.count == 6
            let isAllDigits = number.allSatisfy { $0.isNumber }
            #expect(isSixDigits)
            #expect(isAllDigits)
        }
    }

    @Test func memberNumberDiffersForDistinctIDs() {
        // Not a uniqueness guarantee (hash into a 6-digit space) — but 50
        // sequential-looking transaction ids should not collide in practice.
        let ids = (0..<50).map { "2000000\(100000000 + $0)" }
        let uniqueCount = Set(ids.map { memberNumber(fromTransactionID: $0) }).count
        #expect(uniqueCount == ids.count)
    }

    @Test func memberNumberChangesWithInputChange() {
        let a = memberNumber(fromTransactionID: "2000000123456789")
        let b = memberNumber(fromTransactionID: "2000000123456780")
        #expect(a != b)
    }

    // MARK: - PTMembershipTerm (spec v2.1, subscription-only)

    @Test func membershipTermMemberLineSuffixes() {
        let annual = PTMembershipTerm.annual(renewsOn: "12 Aug 2027").memberLineSuffix
        let monthly = PTMembershipTerm.monthly(renewsOn: "16 Aug 2026", dayText: "the 16th").memberLineSuffix
        let trial = PTMembershipTerm.trial(billsOn: "30 Jul 2026").memberLineSuffix
        #expect(annual == "ANNUAL")
        #expect(monthly == "MONTHLY")
        #expect(trial == "TRIAL")
    }

    @Test func membershipTermStatusTextRenewsAndUppercases() {
        let annual = PTMembershipTerm.annual(renewsOn: "12 Aug 2027").statusText
        let monthly = PTMembershipTerm.monthly(renewsOn: "16 Aug 2026", dayText: "the 16th").statusText
        let trial = PTMembershipTerm.trial(billsOn: "30 Jul 2026").statusText
        #expect(annual == "RENEWS 12 AUG 2027")
        #expect(monthly == "RENEWS 16 AUG 2026")
        #expect(trial == "TRIAL · BILLS 30 JUL 2026")
    }
}
