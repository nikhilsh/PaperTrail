import Testing
import Foundation
@testable import PaperTrail

/// Pure-logic tests for the v2 design system (`PaperTrail/Design/V2/`).
/// Everything else in that folder is SwiftUI view code with no
/// device-independent behavior to assert on — this file covers the one
/// extracted pure helper: `memberNumber(fromTransactionID:)`.
struct V2ComponentsTests {

    // MARK: - memberNumber(fromTransactionID:)

    @Test func memberNumberIsDeterministic() {
        let id = "2000000123456789"
        #expect(memberNumber(fromTransactionID: id) == memberNumber(fromTransactionID: id))
    }

    @Test func memberNumberIsSixDigits() {
        let ids = ["2000000123456789", "", "a", "2000000987654321", "🎉", String(repeating: "x", count: 500)]
        for id in ids {
            let number = memberNumber(fromTransactionID: id)
            #expect(number.count == 6, "expected 6 digits for id \(id.debugDescription), got \(number)")
            #expect(number.allSatisfy(\.isNumber), "expected only digits for id \(id.debugDescription), got \(number)")
        }
    }

    @Test func memberNumberDiffersForDistinctIDs() {
        let ids = (0..<50).map { "2000000\(100000000 + $0)" }
        let numbers = Set(ids.map(memberNumber(fromTransactionID:)))
        // Not a uniqueness guarantee (hash into a 6-digit space) — but 50
        // sequential-looking transaction ids should not collide in practice.
        #expect(numbers.count == ids.count)
    }

    @Test func memberNumberChangesWithInputChange() {
        let a = memberNumber(fromTransactionID: "2000000123456789")
        let b = memberNumber(fromTransactionID: "2000000123456780")
        #expect(a != b)
    }
}
