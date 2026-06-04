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

    // MARK: - Purchase date string parsing

    private func ymd(_ date: Date) -> (Int, Int, Int) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }

    @Test func parsesIsoDate() throws {
        let d = try #require(FoundationModelExtractionService.parsePurchaseDateString("2025-11-23"))
        #expect(ymd(d) == (2025, 11, 23))
    }

    @Test func parsesTextualDateWithoutSwappingDayAndYear() throws {
        // The real-world bug: "23-Nov-25" prefilled as "25 Nov 23". It must be
        // day 23 / Nov / 2025 — day and year not swapped, year not 0023.
        let d = try #require(FoundationModelExtractionService.parsePurchaseDateString("23-Nov-25"))
        #expect(ymd(d) == (2025, 11, 23))
    }

    @Test func parsesDayFirstNumericDate() throws {
        let d = try #require(FoundationModelExtractionService.parsePurchaseDateString("15/01/2026"))
        #expect(ymd(d) == (2026, 1, 15))
    }

    @Test func rejectsUnparseableOrNilDate() {
        #expect(FoundationModelExtractionService.parsePurchaseDateString(nil) == nil)
        #expect(FoundationModelExtractionService.parsePurchaseDateString("not a date") == nil)
        #expect(FoundationModelExtractionService.parsePurchaseDateString("") == nil)
    }

    // MARK: - Locale-aware date convention

    @Test func deviceConventionDerivedFromLocale() {
        #expect(LocaleDateConvention(locale: Locale(identifier: "en_US")).order == .monthFirst)
        #expect(LocaleDateConvention(locale: Locale(identifier: "en_GB")).order == .dayFirst)
        #expect(LocaleDateConvention(locale: Locale(identifier: "en_SG")).order == .dayFirst)
        #expect(LocaleDateConvention(locale: Locale(identifier: "ja_JP")).order == .yearFirst)
    }

    @Test func ambiguousDateResolvedByConvention() throws {
        // 03/05/2025 is genuinely ambiguous and must follow the region.
        let monthFirst = try #require(
            FoundationModelExtractionService.parsePurchaseDateString("03/05/2025", convention: LocaleDateConvention(order: .monthFirst)))
        #expect(ymd(monthFirst) == (2025, 3, 5))   // US: 5 March

        let dayFirst = try #require(
            FoundationModelExtractionService.parsePurchaseDateString("03/05/2025", convention: LocaleDateConvention(order: .dayFirst)))
        #expect(ymd(dayFirst) == (2025, 5, 3))      // SG/UK: 3 May
    }

    @Test func unambiguousDateIgnoresConvention() throws {
        // 25/12/2025 can only be day-first (no 25th month) — both conventions agree.
        for order in [LocaleDateConvention.Order.monthFirst, .dayFirst] {
            let d = try #require(
                FoundationModelExtractionService.parsePurchaseDateString("25/12/2025", convention: LocaleDateConvention(order: order)))
            #expect(ymd(d) == (2025, 12, 25))
        }
    }
}
