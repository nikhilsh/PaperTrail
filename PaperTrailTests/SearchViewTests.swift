//
//  SearchViewTests.swift
//  PaperTrailTests
//
//  Coverage for SearchView's match predicate — the app ships a serial
//  barcode scanner, so search must find records by serial number (partial
//  match, since people type only the last few characters) and by room.
//

import Testing
import Foundation
import SwiftData
@testable import PaperTrail

struct SearchViewTests {

    @MainActor
    private func sampleRecord() -> PurchaseRecord {
        PurchaseRecord(
            productName: "LG Washer",
            merchantName: "Gain City",
            notes: "Bought during the June sale",
            category: "Appliances",
            room: "Laundry Room",
            tags: ["white goods"],
            serialNumber: "SN-9XK42"
        )
    }

    // MARK: - Serial number

    @Test @MainActor func matchesFullSerialNumber() {
        let record = sampleRecord()
        #expect(SearchView.matches(record: record, attachments: [], query: "SN-9XK42"))
    }

    @Test @MainActor func matchesPartialSerialSuffixCaseInsensitively() {
        // People typically type only the last few characters off the barcode.
        let record = sampleRecord()
        #expect(SearchView.matches(record: record, attachments: [], query: "xk42"))
    }

    @Test @MainActor func noMatchWhenSerialAbsentAndNoOtherFieldMatches() {
        let record = sampleRecord()
        #expect(!SearchView.matches(record: record, attachments: [], query: "ZZ-0000"))
    }

    @Test @MainActor func nilSerialDoesNotMatch() {
        let record = PurchaseRecord(productName: "Unrelated Item")
        #expect(!SearchView.matches(record: record, attachments: [], query: "SN-9XK42"))
    }

    // MARK: - Room

    @Test @MainActor func matchesRoomCaseInsensitively() {
        let record = sampleRecord()
        #expect(SearchView.matches(record: record, attachments: [], query: "laundry"))
    }

    @Test @MainActor func nilRoomDoesNotMatch() {
        let record = PurchaseRecord(productName: "Unrelated Item")
        #expect(!SearchView.matches(record: record, attachments: [], query: "Laundry Room"))
    }

    // MARK: - Existing fields still work (no regression)

    @Test @MainActor func stillMatchesProductNameMerchantNotesCategoryTagsAndOcrText() {
        let record = sampleRecord()
        #expect(SearchView.matches(record: record, attachments: [], query: "washer"))
        #expect(SearchView.matches(record: record, attachments: [], query: "gain city"))
        #expect(SearchView.matches(record: record, attachments: [], query: "june sale"))
        #expect(SearchView.matches(record: record, attachments: [], query: "appliances"))
        #expect(SearchView.matches(record: record, attachments: [], query: "white goods"))

        let attachment = Attachment(recordID: record.id, type: .receipt, localFilename: "r.jpg", ocrText: "Total $1479.00")
        #expect(SearchView.matches(record: record, attachments: [attachment], query: "1479"))
    }

    @Test @MainActor func noMatchOnEmptyQueryAgainstUnrelatedText() {
        let record = sampleRecord()
        #expect(!SearchView.matches(record: record, attachments: [], query: "nonexistent"))
    }
}
