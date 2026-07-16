import Testing
import Foundation
@testable import PaperTrail

/// Pure logic tests for `WidgetSnapshotWriter.nearestUpcoming`: nearest-6
/// selection across mixed warranty/return candidates, past-date exclusion,
/// and `WidgetSnapshot`/`WidgetSnapshotItem` Codable round-trip. No
/// SwiftData, no App Group I/O — value types in, value types out.
struct WidgetSnapshotTests {

    private let now = Date(timeIntervalSince1970: 1_752_000_000) // fixed anchor, arbitrary

    private func daysFromNow(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: now)!
    }

    private func item(_ name: String, kind: String, daysFromNow n: Int) -> WidgetSnapshotItem {
        WidgetSnapshotItem(recordID: UUID(), name: name, kind: kind, date: daysFromNow(n))
    }

    // MARK: - Empty

    @Test func emptyCandidatesYieldsEmptySelection() {
        let selected = WidgetSnapshotWriter.nearestUpcoming(from: [], limit: 6, now: now)
        #expect(selected.isEmpty)
    }

    // MARK: - Past-date exclusion

    @Test func excludesPastDates() {
        let candidates = [
            item("Expired Warranty", kind: "warranty", daysFromNow: -1),
            item("Today Warranty", kind: "warranty", daysFromNow: 0),
            item("Future Return", kind: "return", daysFromNow: 5),
        ]
        let selected = WidgetSnapshotWriter.nearestUpcoming(from: candidates, limit: 6, now: now)
        #expect(selected.count == 2)
        #expect(selected.map(\.name) == ["Today Warranty", "Future Return"])
    }

    // MARK: - Nearest-6 across mixed kinds

    @Test func selectsNearestSixAcrossMixedKinds() {
        let candidates = [
            item("Warranty A", kind: "warranty", daysFromNow: 40),
            item("Return A", kind: "return", daysFromNow: 2),
            item("Warranty B", kind: "warranty", daysFromNow: 10),
            item("Return B", kind: "return", daysFromNow: 30),
            item("Warranty C", kind: "warranty", daysFromNow: 1),
            item("Return C", kind: "return", daysFromNow: 60),
            item("Warranty D", kind: "warranty", daysFromNow: 20),
        ]
        let selected = WidgetSnapshotWriter.nearestUpcoming(from: candidates, limit: 6, now: now)
        #expect(selected.count == 6)
        #expect(selected.map(\.name) == [
            "Warranty C", "Return A", "Warranty B", "Warranty D", "Return B", "Warranty A",
        ])
        // "Return C" (60 days out) is the 7th-nearest, so it's dropped.
        #expect(!selected.map(\.name).contains("Return C"))
    }

    @Test func resultIsSortedAscendingByDate() {
        let candidates = [
            item("Later", kind: "warranty", daysFromNow: 15),
            item("Sooner", kind: "return", daysFromNow: 3),
            item("Middle", kind: "warranty", daysFromNow: 8),
        ]
        let selected = WidgetSnapshotWriter.nearestUpcoming(from: candidates, limit: 6, now: now)
        #expect(selected.map(\.name) == ["Sooner", "Middle", "Later"])
    }

    @Test func respectsLimitBelowSix() {
        let candidates = [
            item("A", kind: "warranty", daysFromNow: 1),
            item("B", kind: "return", daysFromNow: 2),
            item("C", kind: "warranty", daysFromNow: 3),
        ]
        let selected = WidgetSnapshotWriter.nearestUpcoming(from: candidates, limit: 2, now: now)
        #expect(selected.count == 2)
        #expect(selected.map(\.name) == ["A", "B"])
    }

    // MARK: - Codable round-trip

    @Test func snapshotRoundTripsThroughJSON() throws {
        let snapshot = WidgetSnapshot(
            generatedAt: now,
            items: [
                item("Blender", kind: "warranty", daysFromNow: 10),
                item("Lamp", kind: "return", daysFromNow: 2),
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        #expect(decoded.items.count == 2)
        #expect(decoded.items.map(\.name) == ["Blender", "Lamp"])
        #expect(decoded.items.map(\.kind) == ["warranty", "return"])
        #expect(decoded.items.map(\.id) == snapshot.items.map(\.id))
        // ISO 8601 loses sub-second precision, so compare at 1-second granularity.
        for (original, roundTripped) in zip(snapshot.items, decoded.items) {
            #expect(abs(original.date.timeIntervalSince(roundTripped.date)) < 1)
        }
    }

    // MARK: - PurchaseRecord -> widgetCandidates

    @Test func recordWithBothDatesProducesTwoCandidates() {
        let record = PurchaseRecord(
            productName: "Espresso Machine",
            purchaseDate: now,
            warrantyExpiryDate: daysFromNow(30),
            returnWindowDays: 14
        )
        let candidates = record.widgetCandidates
        #expect(candidates.count == 2)
        #expect(Set(candidates.map(\.kind)) == ["warranty", "return"])
        #expect(candidates.allSatisfy { $0.recordID == record.id && $0.name == "Espresso Machine" })
        // Regression: both candidates share a `recordID` (same record, one
        // warranty + one return event) — `id` must still be unique per
        // event or SwiftUI `ForEach`/List identity collides in the widget.
        #expect(Set(candidates.map(\.id)).count == 2)
    }

    @Test func recordWithNeitherDateProducesNoCandidates() {
        let record = PurchaseRecord(productName: "Undated Item")
        #expect(record.widgetCandidates.isEmpty)
    }

    // MARK: - Back-compat decode (v3 shelfWidgets additive fields)

    /// A pre-v3 snapshot on disk has no `coveredCount`/`totalCount`/
    /// `totalValueText`/`registerNudge` keys at all. Regression: the four
    /// new fields must decode as `nil` rather than throwing
    /// `DecodingError.keyNotFound`.
    @Test func preV3SnapshotJSONWithoutNewFieldsStillDecodes() throws {
        let json = """
        {
            "generatedAt": "2026-07-16T00:00:00Z",
            "items": [
                {"recordID": "\(UUID().uuidString)", "name": "Blender", "kind": "warranty", "date": "2026-08-01T00:00:00Z"}
            ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))

        #expect(decoded.items.count == 1)
        #expect(decoded.coveredCount == nil)
        #expect(decoded.totalCount == nil)
        #expect(decoded.totalValueText == nil)
        #expect(decoded.registerNudge == nil)
    }

    /// The new fields round-trip through the same encoder/decoder pair the
    /// writer/provider actually use.
    @Test func v3FieldsRoundTripThroughJSON() throws {
        let nudge = WidgetRegisterNudge(recordID: UUID(), name: "Rheem Heater")
        let snapshot = WidgetSnapshot(
            generatedAt: now,
            items: [item("Blender", kind: "warranty", daysFromNow: 10)],
            coveredCount: 4,
            totalCount: 5,
            totalValueText: "SGD 3,116",
            registerNudge: nudge
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        #expect(decoded.coveredCount == 4)
        #expect(decoded.totalCount == 5)
        #expect(decoded.totalValueText == "SGD 3,116")
        #expect(decoded.registerNudge == nudge)
    }

    // MARK: - coverageCounts

    @Test func coverageCountsCountsActiveWarrantiesOnly() {
        let records = [
            PurchaseRecord(productName: "Active", warrantyExpiryDate: daysFromNow(30)),
            PurchaseRecord(productName: "ExpiresToday", warrantyExpiryDate: daysFromNow(0)),
            PurchaseRecord(productName: "Expired", warrantyExpiryDate: daysFromNow(-1)),
            PurchaseRecord(productName: "NoWarranty"),
        ]
        let result = WidgetSnapshotWriter.coverageCounts(for: records, now: now)
        #expect(result.covered == 2) // Active + ExpiresToday
        #expect(result.total == 4)
    }

    @Test func coverageCountsOnEmptyRecordsIsZeroZero() {
        let result = WidgetSnapshotWriter.coverageCounts(for: [], now: now)
        #expect(result.covered == 0)
        #expect(result.total == 0)
    }

    // MARK: - dominantCurrencyTotalText

    @Test func dominantCurrencyTotalTextSumsAndPicksLargestTotal() {
        let records = [
            PurchaseRecord(productName: "A", amount: 1_200, currency: "SGD"),
            PurchaseRecord(productName: "B", amount: 1_916, currency: "SGD"),
            PurchaseRecord(productName: "C", amount: 50, currency: "USD"),
        ]
        #expect(WidgetSnapshotWriter.dominantCurrencyTotalText(for: records) == "SGD 3,116")
    }

    @Test func dominantCurrencyTotalTextDefaultsMissingCurrencyToSGD() {
        let records = [PurchaseRecord(productName: "A", amount: 100, currency: nil)]
        #expect(WidgetSnapshotWriter.dominantCurrencyTotalText(for: records) == "SGD 100")
    }

    @Test func dominantCurrencyTotalTextIsNilWhenNoAmounts() {
        let records = [PurchaseRecord(productName: "A")]
        #expect(WidgetSnapshotWriter.dominantCurrencyTotalText(for: records) == nil)
    }

    @Test func dominantCurrencyTotalTextBreaksTiesAlphabetically() {
        // USD and EUR tie at 100 each — "EUR" should win alphabetically.
        let records = [
            PurchaseRecord(productName: "A", amount: 100, currency: "USD"),
            PurchaseRecord(productName: "B", amount: 100, currency: "EUR"),
        ]
        #expect(WidgetSnapshotWriter.dominantCurrencyTotalText(for: records) == "EUR 100")
    }

    // MARK: - registerNudgeCandidate

    @Test func registerNudgeCandidatePicksSoonestUnregisteredActiveItem() {
        let records = [
            PurchaseRecord(productName: "Registered Soon", warrantyExpiryDate: daysFromNow(5), isRegistered: true),
            PurchaseRecord(productName: "Unregistered Far", warrantyExpiryDate: daysFromNow(90), isRegistered: false),
            PurchaseRecord(productName: "Unregistered Near", warrantyExpiryDate: daysFromNow(10), isRegistered: false),
        ]
        let nudge = WidgetSnapshotWriter.registerNudgeCandidate(for: records, now: now)
        #expect(nudge?.name == "Unregistered Near")
    }

    @Test func registerNudgeCandidateIgnoresExpiredWarranties() {
        let records = [
            PurchaseRecord(productName: "Expired Unregistered", warrantyExpiryDate: daysFromNow(-3), isRegistered: false),
        ]
        #expect(WidgetSnapshotWriter.registerNudgeCandidate(for: records, now: now) == nil)
    }

    @Test func registerNudgeCandidateIgnoresRegisteredItems() {
        let records = [
            PurchaseRecord(productName: "Already Registered", warrantyExpiryDate: daysFromNow(5), isRegistered: true),
        ]
        #expect(WidgetSnapshotWriter.registerNudgeCandidate(for: records, now: now) == nil)
    }

    @Test func registerNudgeCandidateIgnoresItemsWithoutWarranty() {
        let records = [PurchaseRecord(productName: "No Warranty Tracked", isRegistered: false)]
        #expect(WidgetSnapshotWriter.registerNudgeCandidate(for: records, now: now) == nil)
    }

    @Test func registerNudgeCandidateBreaksTiesByProductName() {
        let records = [
            PurchaseRecord(productName: "Zebra Print", warrantyExpiryDate: daysFromNow(5), isRegistered: false),
            PurchaseRecord(productName: "Alpha Kettle", warrantyExpiryDate: daysFromNow(5), isRegistered: false),
        ]
        let nudge = WidgetSnapshotWriter.registerNudgeCandidate(for: records, now: now)
        #expect(nudge?.name == "Alpha Kettle")
    }

    @Test func registerNudgeCandidateOnEmptyRecordsIsNil() {
        #expect(WidgetSnapshotWriter.registerNudgeCandidate(for: [], now: now) == nil)
    }
}
