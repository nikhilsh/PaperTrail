//
//  InsuranceReportBuilderTests.swift
//  PaperTrailTests
//
//  Coverage for InsuranceReport.build: room grouping (including "Unfiled"),
//  per-item sort order (amount desc), and per-currency totals that are never
//  summed across currencies.
//

import Testing
import Foundation
@testable import PaperTrail

struct InsuranceReportBuilderTests {

    private func record(
        name: String,
        room: String? = nil,
        amount: Double? = nil,
        currency: String? = nil,
        category: String? = nil
    ) -> PurchaseRecord {
        PurchaseRecord(productName: name, amount: amount, currency: currency, category: category, room: room)
    }

    // MARK: - Room grouping

    @Test func groupsRecordsByRoomAndSortsRoomsAlphabetically() {
        let records = [
            record(name: "Sofa", room: "Living Room"),
            record(name: "Kettle", room: "Kitchen"),
            record(name: "Drill", room: "Garage"),
        ]
        let report = InsuranceReport.build(records: records, attachments: [])
        #expect(report.sections.map(\.name) == ["Garage", "Kitchen", "Living Room"])
    }

    @Test func nilAndBlankRoomsFallIntoUnfiled() {
        let records = [
            record(name: "A", room: nil),
            record(name: "B", room: ""),
            record(name: "C", room: "   "),
            record(name: "D", room: "Kitchen"),
        ]
        let report = InsuranceReport.build(records: records, attachments: [])
        let unfiled = try! #require(report.sections.first { $0.name == InsuranceReport.unfiledRoomName })
        #expect(unfiled.items.count == 3)
        #expect(report.sections.contains { $0.name == "Kitchen" })
    }

    @Test func itemsWithinARoomSortByAmountDescending() {
        let records = [
            record(name: "Cheap", room: "Kitchen", amount: 20),
            record(name: "Pricey", room: "Kitchen", amount: 500),
            record(name: "Mid", room: "Kitchen", amount: 100),
        ]
        let report = InsuranceReport.build(records: records, attachments: [])
        let kitchen = try! #require(report.sections.first { $0.name == "Kitchen" })
        #expect(kitchen.items.map(\.name) == ["Pricey", "Mid", "Cheap"])
    }

    @Test func itemsWithNilAmountSortToTheEnd() {
        let records = [
            record(name: "NoPrice", room: "Kitchen", amount: nil),
            record(name: "Priced", room: "Kitchen", amount: 50),
        ]
        let report = InsuranceReport.build(records: records, attachments: [])
        let kitchen = try! #require(report.sections.first { $0.name == "Kitchen" })
        #expect(kitchen.items.map(\.name) == ["Priced", "NoPrice"])
    }

    // MARK: - Per-currency totals

    @Test func perRoomTotalsAreKeyedByCurrencyNeverSummedAcrossCurrencies() {
        let records = [
            record(name: "USD Item", room: "Office", amount: 100, currency: "USD"),
            record(name: "SGD Item", room: "Office", amount: 200, currency: "SGD"),
        ]
        let report = InsuranceReport.build(records: records, attachments: [])
        let office = try! #require(report.sections.first { $0.name == "Office" })
        #expect(office.purchaseTotalsByCurrency["USD"] == 100)
        #expect(office.purchaseTotalsByCurrency["SGD"] == 200)
        #expect(office.purchaseTotalsByCurrency.count == 2)
    }

    @Test func nilCurrencyBucketsUnderUnspecifiedNotFabricatedSGD() {
        let records = [record(name: "No Currency", room: "Office", amount: 50, currency: nil)]
        let report = InsuranceReport.build(records: records, attachments: [])
        let office = try! #require(report.sections.first { $0.name == "Office" })
        #expect(office.purchaseTotalsByCurrency[InsuranceReport.unspecifiedCurrency] == 50)
        #expect(office.purchaseTotalsByCurrency["SGD"] == nil)
    }

    @Test func unspecifiedCurrencyBucketNeverMergesWithARealCurrencyTotal() {
        let records = [
            record(name: "No Currency", room: "Office", amount: 50, currency: nil),
            record(name: "SGD Item", room: "Office", amount: 200, currency: "SGD"),
        ]
        let report = InsuranceReport.build(records: records, attachments: [])
        let office = try! #require(report.sections.first { $0.name == "Office" })
        #expect(office.purchaseTotalsByCurrency[InsuranceReport.unspecifiedCurrency] == 50)
        #expect(office.purchaseTotalsByCurrency["SGD"] == 200)
        #expect(office.purchaseTotalsByCurrency.count == 2)
    }

    @Test func grandTotalsAggregateAcrossRoomsPerCurrency() {
        let records = [
            record(name: "A", room: "Kitchen", amount: 100, currency: "USD"),
            record(name: "B", room: "Garage", amount: 50, currency: "USD"),
            record(name: "C", room: "Garage", amount: 30, currency: "SGD"),
        ]
        let report = InsuranceReport.build(records: records, attachments: [])
        #expect(report.grandPurchaseTotalsByCurrency["USD"] == 150)
        #expect(report.grandPurchaseTotalsByCurrency["SGD"] == 30)
        #expect(report.totalItemCount == 3)
    }

    @Test func estimatedTotalsUseDepreciationEstimator() {
        let asOf = Date.now
        let purchaseDate = asOf.addingTimeInterval(-365.2425 * 86_400) // ~1 year ago
        let electronics = PurchaseRecord(
            productName: "Laptop", purchaseDate: purchaseDate, amount: 1000, currency: "USD",
            category: "Electronics", room: "Office")
        let report = InsuranceReport.build(records: [electronics], attachments: [], asOf: asOf)
        let office = try! #require(report.sections.first { $0.name == "Office" })
        let estimated = try! #require(office.estimatedTotalsByCurrency["USD"])
        #expect(abs(estimated - 750) < 1.0) // 25%/yr electronics depreciation
    }

    // MARK: - Thumbnail attachment selection

    @Test func prefersProductImageAttachmentOverFirstAttachment() {
        let rec = PurchaseRecord(productName: "Camera", room: "Office")
        let receipt = Attachment(recordID: rec.id, type: .receipt, localFilename: "receipt.jpg")
        let productPhoto = Attachment(recordID: rec.id, type: .other, localFilename: "product.jpg")
        rec.productImageAttachmentID = productPhoto.id
        let report = InsuranceReport.build(records: [rec], attachments: [receipt, productPhoto])
        let item = report.sections.first?.items.first
        #expect(item?.thumbnailFilename == "product.jpg")
    }

    @Test func fallsBackToFirstAttachmentWhenNoProductImageSet() {
        let rec = PurchaseRecord(productName: "Camera", room: "Office")
        let receipt = Attachment(recordID: rec.id, type: .receipt, localFilename: "receipt.jpg")
        let report = InsuranceReport.build(records: [rec], attachments: [receipt])
        let item = report.sections.first?.items.first
        #expect(item?.thumbnailFilename == "receipt.jpg")
    }

    @Test func nilWhenRecordHasNoAttachments() {
        let rec = PurchaseRecord(productName: "Camera", room: "Office")
        let report = InsuranceReport.build(records: [rec], attachments: [])
        let item = report.sections.first?.items.first
        #expect(item?.thumbnailFilename == nil)
    }
}
