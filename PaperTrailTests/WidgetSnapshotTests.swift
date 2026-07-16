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
}
