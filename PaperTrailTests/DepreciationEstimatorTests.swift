//
//  DepreciationEstimatorTests.swift
//  PaperTrailTests
//
//  Coverage for straight-line depreciation rates by category, the 20% floor,
//  nil-amount passthrough, and future-purchase-date clamping.
//

import Testing
import Foundation
@testable import PaperTrail

struct DepreciationEstimatorTests {

    private func date(yearsAgo: Double, from reference: Date = .now) -> Date {
        reference.addingTimeInterval(-yearsAgo * 365.2425 * 86_400)
    }

    @Test func nilAmountReturnsNil() {
        let value = DepreciationEstimator.estimatedCurrentValue(
            amount: nil, category: "Electronics", purchaseDate: .now, asOf: .now)
        #expect(value == nil)
    }

    @Test func electronicsDepreciatesAt25PercentPerYear() throws {
        let asOf = Date.now
        let value = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Electronics", purchaseDate: date(yearsAgo: 1, from: asOf), asOf: asOf))
        #expect(abs(value - 750) < 0.5)
    }

    @Test func computersAndPhonesMatchElectronicsRate() throws {
        let asOf = Date.now
        let computer = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Computer", purchaseDate: date(yearsAgo: 1, from: asOf), asOf: asOf))
        let phone = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Smartphone", purchaseDate: date(yearsAgo: 1, from: asOf), asOf: asOf))
        #expect(abs(computer - 750) < 0.5)
        #expect(abs(phone - 750) < 0.5)
    }

    @Test func appliancesDepreciateAt15PercentPerYear() throws {
        let asOf = Date.now
        let value = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Appliance", purchaseDate: date(yearsAgo: 1, from: asOf), asOf: asOf))
        #expect(abs(value - 850) < 0.5)
    }

    @Test func furnitureDepreciatesAt15PercentPerYear() throws {
        let asOf = Date.now
        let value = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Furniture", purchaseDate: date(yearsAgo: 1, from: asOf), asOf: asOf))
        #expect(abs(value - 850) < 0.5)
    }

    @Test func toolsDepreciateAt10PercentPerYear() throws {
        let asOf = Date.now
        let value = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Power Tools", purchaseDate: date(yearsAgo: 1, from: asOf), asOf: asOf))
        #expect(abs(value - 900) < 0.5)
    }

    @Test func jewelryAndWatchesDoNotDepreciate() throws {
        let asOf = Date.now
        let jewelry = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Fine Jewelry", purchaseDate: date(yearsAgo: 10, from: asOf), asOf: asOf))
        let watch = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Watches", purchaseDate: date(yearsAgo: 10, from: asOf), asOf: asOf))
        #expect(abs(jewelry - 1000) < 0.01)
        #expect(abs(watch - 1000) < 0.01)
    }

    @Test func unmatchedCategoryUsesDefault10Percent() throws {
        let asOf = Date.now
        let value = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Sports", purchaseDate: date(yearsAgo: 1, from: asOf), asOf: asOf))
        #expect(abs(value - 900) < 0.5)
    }

    @Test func nilCategoryUsesDefaultRate() throws {
        let asOf = Date.now
        let value = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: nil, purchaseDate: date(yearsAgo: 1, from: asOf), asOf: asOf))
        #expect(abs(value - 900) < 0.5)
    }

    @Test func floorsAt20PercentOfPurchaseAmount() throws {
        // 25%/yr electronics over 10 years would go to 0 (and below) without a floor.
        let asOf = Date.now
        let value = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Electronics", purchaseDate: date(yearsAgo: 10, from: asOf), asOf: asOf))
        #expect(abs(value - 200) < 0.01)
    }

    @Test func futurePurchaseDateClampsToZeroYearsElapsed() throws {
        let asOf = Date.now
        let future = asOf.addingTimeInterval(30 * 86_400)
        let value = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Electronics", purchaseDate: future, asOf: asOf))
        #expect(abs(value - 1000) < 0.01)
    }

    @Test func nilPurchaseDateTreatedAsZeroYearsElapsed() throws {
        let asOf = Date.now
        let value = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 1000, category: "Electronics", purchaseDate: nil, asOf: asOf))
        #expect(abs(value - 1000) < 0.01)
    }

    @Test func roundsToTwoDecimalPlaces() throws {
        let asOf = Date.now
        let value = try #require(DepreciationEstimator.estimatedCurrentValue(
            amount: 333.33, category: "Furniture", purchaseDate: date(yearsAgo: 1, from: asOf), asOf: asOf))
        let scaled = value * 100
        #expect(abs(scaled - scaled.rounded()) < 0.001)
    }
}
