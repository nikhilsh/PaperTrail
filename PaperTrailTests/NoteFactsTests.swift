import Testing
import Foundation
@testable import PaperTrail

/// Notes carry extraction facts, never boilerplate — and user prose is
/// sacred (only labels the app itself writes become chips).
struct NoteFactsTests {

    @Test func composeBuildsOneLinePerFact() {
        let notes = NoteFacts.composeNotes(
            orderReference: "IV-2081",
            taxAmount: 21.11,
            currency: "SGD",
            vatId: "201234567M"
        )
        let lines = notes!.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "Order no: IV-2081")
        #expect(lines[1].hasPrefix("Tax: ") && lines[1].contains("21.11"))
        #expect(lines[2] == "Merchant tax ID: 201234567M")
    }

    @Test func composeReturnsNilNotBoilerplateWhenNothingFound() {
        #expect(NoteFacts.composeNotes(orderReference: nil, taxAmount: nil, currency: nil, vatId: nil) == nil)
        #expect(NoteFacts.composeNotes(orderReference: "", taxAmount: nil, currency: "SGD", vatId: "") == nil)
    }

    @Test func composeWithoutCurrencyStillFormatsTax() {
        let notes = NoteFacts.composeNotes(orderReference: nil, taxAmount: 5.5, currency: nil, vatId: nil)
        #expect(notes == "Tax: 5.50")
    }

    @Test func parseRoundTripsComposedFacts() {
        let notes = NoteFacts.composeNotes(
            orderReference: "SO-99182",
            taxAmount: nil,
            currency: nil,
            vatId: "T08GB0021A"
        )!
        let parsed = NoteFacts.parse(notes)
        #expect(parsed.facts.map(\.label) == ["Order no", "Merchant tax ID"])
        #expect(parsed.facts.map(\.value) == ["SO-99182", "T08GB0021A"])
        #expect(parsed.freeText.isEmpty)
    }

    @Test func userProseIsNeverChipified() {
        let parsed = NoteFacts.parse("TODO: buy water filters\nReceipt lives in the kitchen drawer")
        #expect(parsed.facts.isEmpty)
        #expect(parsed.freeText == "TODO: buy water filters\nReceipt lives in the kitchen drawer")
    }

    @Test func mixedNotesSplitFactsFromProse() {
        let parsed = NoteFacts.parse("Order no: IV-2081\nExtended warranty till 2028, card in drawer")
        #expect(parsed.facts == [NoteFacts.Fact(label: "Order no", value: "IV-2081")])
        #expect(parsed.freeText == "Extended warranty till 2028, card in drawer")
    }

    @Test func emptyValueFactLineStaysProse() {
        let parsed = NoteFacts.parse("Order no: ")
        #expect(parsed.facts.isEmpty)
    }
}
