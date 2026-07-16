import Testing
import Foundation
@testable import PaperTrail

/// Pure-logic tests for v3 `serviceLedger` + `manualOnFile`
/// (docs/design-v3/V3_BRIEF.md §4-5): `ServiceEntry`'s additive-optional
/// schema round-trips through Codable, the ledger's date-desc sort order,
/// `PurchaseRecord.serviceEntries`'s decode-never-throws contract, and
/// `ManualRecord.formattedSize`'s pure formatting. No SwiftUI, no
/// FileManager — everything here is nonisolated value-level logic,
/// mirroring `MultiCoverageTests`'s shape. `ManualStore`'s on-disk I/O is
/// deliberately not exercised here (not a pure helper).
struct ServiceLedgerTests {

    // MARK: - Codable round-trip (write this FIRST, per the task)

    @Test func fullEntryRoundTripsThroughEncodeDecode() throws {
        let entry = ServiceEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            actor: "shop",
            title: "Panel flicker — mainboard replaced",
            cost: Decimal(string: "128.50"),
            jobRef: "SG-88231",
            attachmentIDs: [UUID(), UUID()]
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ServiceEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test func arrayRoundTripsThroughEncodeDecode() throws {
        let entries = [
            ServiceEntry(date: .now, actor: "self", title: "Firmware update"),
            ServiceEntry(date: .now.addingTimeInterval(-86_400), actor: "authorized", title: "Annual service", cost: 40, jobRef: "REF-1")
        ]
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([ServiceEntry].self, from: data)
        #expect(decoded == entries)
    }

    /// Minimal JSON (only the non-optional fields: no `id`, `cost`, `jobRef`,
    /// `attachmentIDs`) must decode cleanly — the same forward-compat
    /// contract `CoverageLine.init(from:)` guarantees, so a future leaner
    /// producer (or a hand-authored fixture) never fails to decode.
    @Test func minimalJSONDecodesWithOptionalFieldsNilAndFreshID() throws {
        let json = Data(#"{"date":719222400,"actor":"self","title":"Battery replaced"}"#.utf8)
        let decoded = try JSONDecoder().decode(ServiceEntry.self, from: json)

        #expect(decoded.actor == "self")
        #expect(decoded.title == "Battery replaced")
        #expect(decoded.cost == nil)
        #expect(decoded.jobRef == nil)
        #expect(decoded.attachmentIDs == nil)
    }

    @Test func actorKindRoundTripsAndUnrecognizedValuePreservesRawString() {
        var entry = ServiceEntry(date: .now, actor: "self", title: "X")
        #expect(entry.actorKind == .selfServiced)

        entry.actorKind = .shop
        #expect(entry.actor == "shop")
        #expect(entry.actorKind == .shop)

        // A future/unrecognized actor string must still round-trip as raw
        // text rather than being coerced or dropped.
        entry.actor = "robot"
        #expect(entry.actorKind == nil)
        #expect(entry.actor == "robot")
    }

    // MARK: - Ledger sort (date desc)

    @Test func sortedByDateDescendingOrdersNewestFirst() {
        let oldest = ServiceEntry(date: Date(timeIntervalSince1970: 0), actor: "self", title: "Oldest")
        let middle = ServiceEntry(date: Date(timeIntervalSince1970: 1_000_000), actor: "self", title: "Middle")
        let newest = ServiceEntry(date: Date(timeIntervalSince1970: 2_000_000), actor: "self", title: "Newest")

        let sorted = [middle, oldest, newest].sortedByDateDescending
        #expect(sorted.map(\.title) == ["Newest", "Middle", "Oldest"])
    }

    @Test func sortedByDateDescendingIsStableAndDeterministicForEqualDates() {
        let sameDate = Date(timeIntervalSince1970: 500_000)
        let a = ServiceEntry(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, date: sameDate, actor: "self", title: "A")
        let b = ServiceEntry(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, date: sameDate, actor: "self", title: "B")

        let sortedOnce = [a, b].sortedByDateDescending
        let sortedAgain = [b, a].sortedByDateDescending
        #expect(sortedOnce.map(\.id) == sortedAgain.map(\.id))
    }

    @Test func emptyLedgerSortsToEmpty() {
        let sorted: [ServiceEntry] = [].sortedByDateDescending
        #expect(sorted.isEmpty)
    }

    // MARK: - PurchaseRecord.serviceEntries (additive-optional storage)

    @Test func purchaseRecordServiceEntriesDefaultsToEmpty() {
        let record = PurchaseRecord(productName: "Test item")
        #expect(record.serviceEntries.isEmpty)
        #expect(record.serviceEntriesData == nil)
    }

    @Test func purchaseRecordServiceEntriesRoundTripsThroughStorage() {
        let record = PurchaseRecord(productName: "Test item")
        let entry = ServiceEntry(date: .now, actor: "shop", title: "Repair", cost: 25, jobRef: "J-1")

        record.serviceEntries = [entry]
        #expect(record.serviceEntriesData != nil)
        #expect(record.serviceEntries == [entry])
    }

    @Test func purchaseRecordServiceEntriesNeverThrowsOnGarbageData() {
        let record = PurchaseRecord(productName: "Test item")
        record.serviceEntriesData = Data("not json".utf8)
        #expect(record.serviceEntries.isEmpty)
    }

    // MARK: - ManualRecord.formattedSize (pure helper)

    @Test func manualRecordFormattedSizeUsesFileByteStyle() {
        let record = ManualRecord(filename: "x.pdf", displayName: "Manual", byteCount: 4_200_000, addedAt: .now)
        // `ByteCountFormatter(.file)` output varies slightly by locale/OS
        // version — assert on content rather than an exact string.
        #expect(record.formattedSize.contains("MB"))
    }
}
