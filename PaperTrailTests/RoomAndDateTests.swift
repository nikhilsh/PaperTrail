//
//  RoomAndDateTests.swift
//  PaperTrailTests
//
//  Coverage for the room option list and the purchase-date normalizer
//  (the fix for 2-digit years parsing as year 0023).
//

import Testing
import Foundation
@testable import PaperTrail

struct RoomAndDateTests {

    private func date(year: Int, month: Int = 6, day: Int = 1) -> Date {
        let cal = Calendar(identifier: .gregorian)
        return cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func year(of date: Date) -> Int {
        Calendar(identifier: .gregorian).component(.year, from: date)
    }

    // MARK: - Purchase date normalization

    @Test func liftsTwoDigitYearIntoThe2000s() throws {
        // The bug: "23" parsed as year 0023. It should become 2023.
        let fixed = try #require(FoundationModelExtractionService.normalizePurchaseDate(date(year: 23)))
        #expect(year(of: fixed) == 2023)
    }

    @Test func keepsPlausibleFourDigitYear() throws {
        let fixed = try #require(FoundationModelExtractionService.normalizePurchaseDate(date(year: 2024)))
        #expect(year(of: fixed) == 2024)
    }

    @Test func rejectsImplausibleDates() {
        #expect(FoundationModelExtractionService.normalizePurchaseDate(nil) == nil)
        #expect(FoundationModelExtractionService.normalizePurchaseDate(date(year: 1990)) == nil)  // pre-2015
        #expect(FoundationModelExtractionService.normalizePurchaseDate(date(year: 10)) == nil)    // 0010 → 2010, still < 2015
        // Far future → rejected.
        let future = Date.now.addingTimeInterval(400 * 86_400)
        #expect(FoundationModelExtractionService.normalizePurchaseDate(future) == nil)
    }

    // MARK: - Room options

    @Test func suggestionsIncludeDefaultsAndCustom() {
        let result = RoomOptions.suggestions(existing: ["Garage", "Wine Cellar"])
        #expect(result.contains("Kitchen"))      // default
        #expect(result.contains("Garage"))       // custom carried forward
        #expect(result.contains("Wine Cellar"))
    }

    @Test func suggestionsDedupeCaseInsensitivelyAndSort() {
        let result = RoomOptions.suggestions(existing: ["living room", "  ", "KITCHEN"])
        // "living room"/"KITCHEN" collapse into the existing defaults (one each).
        #expect(result.filter { $0.lowercased() == "living room" }.count == 1)
        #expect(result.filter { $0.lowercased() == "kitchen" }.count == 1)
        // Sorted ascending, case-insensitive.
        #expect(result == result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        // Blank entries dropped.
        #expect(!result.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }))
    }
}
