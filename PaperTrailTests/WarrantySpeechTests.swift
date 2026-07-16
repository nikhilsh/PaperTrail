//
//  WarrantySpeechTests.swift
//  PaperTrailTests
//
//  Coverage for the spoken-word phrasing helpers behind the App Intents
//  (Siri/Shortcuts) surface — PaperTrail/AppIntents/WarrantySpeech.swift.
//

import Testing
import Foundation
@testable import PaperTrail

struct WarrantySpeechTests {

    private func date(daysFromNow: Int, reference: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: daysFromNow, to: reference)!
    }

    // MARK: - statusSentence

    @Test func speaksNoWarrantyInfoWhenExpiryMissing() {
        let sentence = WarrantySpeech.statusSentence(productName: "LG Washer", expiryDate: nil)
        #expect(sentence == "Your LG Washer has no warranty info.")
    }

    @Test func speaksExpiredWithDate() {
        let now = date(daysFromNow: 0)
        let expiry = Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 12))!
        let sentence = WarrantySpeech.statusSentence(productName: "LG Washer", expiryDate: expiry, now: now)
        #expect(sentence == "Your LG Washer's warranty expired on 12 Mar 2024.")
    }

    @Test func speaksCoveredWithRemainingTime() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 12))!
        let expiry = Calendar.current.date(from: DateComponents(year: 2027, month: 3, day: 12))!
        let sentence = WarrantySpeech.statusSentence(productName: "LG Washer", expiryDate: expiry, now: now)
        #expect(sentence == "Your LG Washer is covered until 12 Mar 2027 — 8 months left.")
    }

    // MARK: - remainingPhrase

    @Test func remainingPhraseUsesDaysUnderTwoWeeks() {
        let now = date(daysFromNow: 0)
        #expect(WarrantySpeech.remainingPhrase(from: now, to: date(daysFromNow: 1, reference: now)) == "1 day")
        #expect(WarrantySpeech.remainingPhrase(from: now, to: date(daysFromNow: 5, reference: now)) == "5 days")
    }

    @Test func remainingPhraseUsesWeeksUnderTwoMonths() {
        let now = date(daysFromNow: 0)
        #expect(WarrantySpeech.remainingPhrase(from: now, to: date(daysFromNow: 20, reference: now)) == "2 weeks")
    }

    @Test func remainingPhraseUsesMonthsUnderOneYear() {
        let now = date(daysFromNow: 0)
        #expect(WarrantySpeech.remainingPhrase(from: now, to: date(daysFromNow: 90, reference: now)) == "3 months")
    }

    @Test func remainingPhraseUsesYearsAtOrOverOneYear() {
        let now = date(daysFromNow: 0)
        #expect(WarrantySpeech.remainingPhrase(from: now, to: date(daysFromNow: 400, reference: now)) == "1 year")
        #expect(WarrantySpeech.remainingPhrase(from: now, to: date(daysFromNow: 800, reference: now)) == "2 years")
    }

    // MARK: - snippetAnswer

    @Test func snippetAnswerHandlesMissingExpiry() {
        #expect(WarrantySpeech.snippetAnswer(expiryDate: nil) == "No warranty info on file.")
    }

    @Test func snippetAnswerHandlesExpired() {
        let now = date(daysFromNow: 0)
        let expiry = Calendar.current.date(from: DateComponents(year: 2024, month: 3, day: 12))!
        #expect(WarrantySpeech.snippetAnswer(expiryDate: expiry, now: now) == "No — expired on 12 Mar 2024.")
    }

    @Test func snippetAnswerHandlesCovered() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 12))!
        let expiry = Calendar.current.date(from: DateComponents(year: 2027, month: 9, day: 12))!
        #expect(WarrantySpeech.snippetAnswer(expiryDate: expiry, now: now) == "Yes — 14 months left. Expires 12 Sep 2027.")
    }

    // MARK: - progressElapsed

    @Test func progressElapsedIsZeroWithNoExpiry() {
        #expect(WarrantySpeech.progressElapsed(purchaseDate: nil, expiryDate: nil) == 0)
    }

    @Test func progressElapsedIsOneWhenExpired() {
        let now = date(daysFromNow: 0)
        let expiry = date(daysFromNow: -10, reference: now)
        #expect(WarrantySpeech.progressElapsed(purchaseDate: nil, expiryDate: expiry, now: now) == 1)
    }

    @Test func progressElapsedIsHalfWithNoPurchaseDateAnchor() {
        let now = date(daysFromNow: 0)
        let expiry = date(daysFromNow: 100, reference: now)
        #expect(WarrantySpeech.progressElapsed(purchaseDate: nil, expiryDate: expiry, now: now) == 0.5)
    }

    @Test func progressElapsedInterpolatesBetweenPurchaseAndExpiry() {
        let now = date(daysFromNow: 0)
        let purchase = date(daysFromNow: -50, reference: now)
        let expiry = date(daysFromNow: 50, reference: now)
        // 50 of 100 days elapsed.
        #expect(abs(WarrantySpeech.progressElapsed(purchaseDate: purchase, expiryDate: expiry, now: now) - 0.5) < 0.01)
    }

    @Test func progressElapsedClampsToUnitRange() {
        let now = date(daysFromNow: 0)
        let purchase = date(daysFromNow: -200, reference: now)
        let expiry = date(daysFromNow: -100, reference: now) // already past expiry
        #expect(WarrantySpeech.progressElapsed(purchaseDate: purchase, expiryDate: expiry, now: now) == 1)
    }

    // MARK: - expiringSoonSummary

    @Test func expiringSoonSummaryHandlesEmptyList() {
        #expect(WarrantySpeech.expiringSoonSummary(records: []) == "No warranties are expiring in the next 60 days.")
    }

    @Test func expiringSoonSummaryUsesSingularForOneItem() {
        let d = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 20))!
        let sentence = WarrantySpeech.expiringSoonSummary(records: [(name: "AirPods Pro", date: d)])
        #expect(sentence == "1 warranty expires soon: AirPods Pro on 20 Jul.")
    }

    @Test func expiringSoonSummaryNamesUpToThreeAndCountsAll() {
        let d1 = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 20))!
        let d2 = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 3))!
        let d3 = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let d4 = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let sentence = WarrantySpeech.expiringSoonSummary(records: [
            (name: "AirPods Pro", date: d1),
            (name: "LG Washer", date: d2),
            (name: "Dyson Vacuum", date: d3),
            (name: "Instant Pot", date: d4)
        ])
        #expect(sentence == "4 warranties expire soon: AirPods Pro on 20 Jul, LG Washer on 3 Aug, Dyson Vacuum on 10 Aug.")
    }
}
