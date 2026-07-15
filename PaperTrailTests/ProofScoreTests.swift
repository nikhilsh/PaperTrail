import Testing
import Foundation
@testable import PaperTrail

/// Verifies the Proof Score scorer: component weights, level boundaries, and
/// missingItems ordering. `ProofScore` is a pure function over
/// `ProofScoreSnapshot`, so no SwiftData/ModelContext is needed here.
struct ProofScoreTests {

    private func snapshot(
        hasAttachment: Bool = false,
        purchaseDate: Date? = nil,
        amount: Double? = nil,
        warrantyExpiryDate: Date? = nil,
        serialNumber: String? = nil,
        productImageAttachmentID: UUID? = nil
    ) -> ProofScoreSnapshot {
        ProofScoreSnapshot(
            hasAttachment: hasAttachment,
            purchaseDate: purchaseDate,
            amount: amount,
            warrantyExpiryDate: warrantyExpiryDate,
            serialNumber: serialNumber,
            productImageAttachmentID: productImageAttachmentID
        )
    }

    // MARK: Totals

    @Test func allComplete_scores100() {
        let snap = snapshot(
            hasAttachment: true,
            purchaseDate: .now,
            amount: 199.0,
            warrantyExpiryDate: .now,
            serialNumber: "SN-1",
            productImageAttachmentID: UUID()
        )
        let result = ProofScore(snapshot: snap)
        #expect(result.score == 100)
        #expect(result.level == .claimReady)
        #expect(result.missingItems.isEmpty)
    }

    @Test func empty_scores0() {
        let result = ProofScore(snapshot: snapshot())
        #expect(result.score == 0)
        #expect(result.level == .needsProof)
        #expect(result.missingItems.count == 6)
    }

    // MARK: Component weights

    @Test func attachment_worth30() {
        let result = ProofScore(snapshot: snapshot(hasAttachment: true))
        #expect(result.score == 30)
    }

    @Test func purchaseDate_worth15() {
        let result = ProofScore(snapshot: snapshot(purchaseDate: .now))
        #expect(result.score == 15)
    }

    @Test func amount_worth15() {
        let result = ProofScore(snapshot: snapshot(amount: 50))
        #expect(result.score == 15)
    }

    @Test func warrantyExpiryDate_worth15() {
        let result = ProofScore(snapshot: snapshot(warrantyExpiryDate: .now))
        #expect(result.score == 15)
    }

    @Test func serialNumber_worth15() {
        let result = ProofScore(snapshot: snapshot(serialNumber: "SN-1"))
        #expect(result.score == 15)
    }

    @Test func emptySerialNumber_doesNotCount() {
        let result = ProofScore(snapshot: snapshot(serialNumber: ""))
        #expect(result.score == 0)
    }

    @Test func productPhoto_worth10() {
        let result = ProofScore(snapshot: snapshot(productImageAttachmentID: UUID()))
        #expect(result.score == 10)
    }

    // MARK: Level boundaries

    @Test func score59_needsProof() {
        // 30 (attachment) + 15 (date) + 15 (amount) - 1pt short of warranty date's
        // 15 isn't representable exactly, so build 59 from an explicit assertion
        // on the boundary function instead of a snapshot combination.
        #expect(ProofScore.Level.level(forScore: 59) == .needsProof)
    }

    @Test func score60_nearlyThere() {
        #expect(ProofScore.Level.level(forScore: 60) == .nearlyThere)
    }

    @Test func score89_nearlyThere() {
        #expect(ProofScore.Level.level(forScore: 89) == .nearlyThere)
    }

    @Test func score90_claimReady() {
        #expect(ProofScore.Level.level(forScore: 90) == .claimReady)
    }

    // MARK: missingItems ordering (points desc, ties in declared order)

    @Test func missingItems_orderedByPointsDescending() {
        let result = ProofScore(snapshot: snapshot())
        #expect(result.missingItems == [
            "No document attached",
            "No purchase date",
            "No purchase amount",
            "No warranty expiry date",
            "No serial number",
            "No product photo"
        ])
    }

    // MARK: Display strings

    @Test func claimReadyLevelDisplaysAsProofComplete() {
        #expect(ProofScore.Level.claimReady.rawValue == "Proof complete")
    }

    @Test func missingItems_skipsPresentComponents() {
        let result = ProofScore(snapshot: snapshot(hasAttachment: true, amount: 20))
        #expect(result.missingItems == [
            "No purchase date",
            "No warranty expiry date",
            "No serial number",
            "No product photo"
        ])
    }
}
