import Testing
import Foundation
@testable import PaperTrail

/// Pure-logic tests for v3 `multiCoverage` (docs/design-v3/V3_BRIEF.md §2-3):
/// `CoverageLine`'s additive-optional schema decodes pre-v3 JSON unchanged,
/// active/expired derivation, the longest-live-line + summary math in
/// `MultiCoveragePassportMath.swift`, and `CoverageReminders`'s 7-day dedupe
/// grouping + identifier format. No SwiftUI, no `UNUserNotificationCenter` —
/// everything here is nonisolated value-level logic, mirroring
/// `CoveragePassportTests`/`NotificationIdentifierTests`'s shape.
struct MultiCoverageTests {

    // MARK: - Codable back-compat (write this FIRST, per the task)

    /// Pre-v3 persisted JSON only ever had `label`/`covered` — this must
    /// decode into the extended struct unchanged, with all four new fields
    /// `nil`, so existing CloudKit records migrate for free.
    @Test func oldTwoFieldJSONDecodesWithNewFieldsNil() throws {
        let oldJSON = Data(#"{"label":"Parts & labour","covered":true}"#.utf8)
        let decoded = try JSONDecoder().decode(CoverageLine.self, from: oldJSON)

        #expect(decoded.label == "Parts & labour")
        #expect(decoded.covered == true)
        #expect(decoded.startDate == nil)
        #expect(decoded.endDate == nil)
        #expect(decoded.kind == nil)
        #expect(decoded.coveredItems == nil)
    }

    /// Same, but decoding an *array* — the actual shape
    /// `PurchaseRecord.coverageLinesData` stores.
    @Test func oldTwoFieldArrayJSONDecodesUnchanged() throws {
        let oldJSON = Data(#"[{"label":"Parts","covered":true},{"label":"Accidental damage","covered":false}]"#.utf8)
        let decoded = try JSONDecoder().decode([CoverageLine].self, from: oldJSON)

        #expect(decoded.count == 2)
        #expect(decoded[0] == CoverageLine(label: "Parts", covered: true))
        #expect(decoded[1] == CoverageLine(label: "Accidental damage", covered: false))
    }

    @Test func newFieldsRoundTripThroughEncodeDecode() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_750_000_000)
        let line = CoverageLine(
            label: "Extended warranty",
            covered: true,
            startDate: start,
            endDate: end,
            kind: "extended",
            coveredItems: ["Panel defects only"]
        )
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(CoverageLine.self, from: data)
        #expect(decoded == line)
    }

    @Test func kindEnumRoundTripsAndUnrecognizedValuePreservesRawString() {
        var line = CoverageLine(label: "X", covered: true)
        line.kindEnum = .insurance
        #expect(line.kind == "insurance")
        #expect(line.kindEnum == .insurance)

        // A future/unrecognized kind string must still round-trip as raw
        // text rather than being coerced or dropped.
        line.kind = "extended-plus-plus"
        #expect(line.kindEnum == nil)
        #expect(line.kind == "extended-plus-plus")
    }

    // MARK: - Active/expired derivation

    private func daysFromNow(_ n: Int, from now: Date = .now) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: now)!
    }

    @Test func lineWithNoEndDateFallsBackToCoveredFlag() {
        let covered = CoverageLine(label: "Parts", covered: true)
        let notCovered = CoverageLine(label: "Accidental damage", covered: false)
        #expect(covered.isActive() == true)
        #expect(notCovered.isActive() == false)
    }

    @Test func lineWithFutureEndDateIsActiveRegardlessOfCoveredFlag() {
        let now = Date.now
        var line = CoverageLine(label: "Extended", covered: false) // covered=false, but dated+future
        line.endDate = daysFromNow(30, from: now)
        #expect(line.isActive(now: now) == true)
    }

    @Test func lineWithPastEndDateIsExpiredRegardlessOfCoveredFlag() {
        let now = Date.now
        var line = CoverageLine(label: "Warranty", covered: true) // covered=true, but dated+past
        line.endDate = daysFromNow(-1, from: now)
        #expect(line.isActive(now: now) == false)
    }

    @Test func lineEndingTodayIsStillActive() {
        let now = Date.now
        var line = CoverageLine(label: "Warranty", covered: false)
        line.endDate = Calendar.current.startOfDay(for: now)
        #expect(line.isActive(now: now) == true)
    }

    // MARK: - multiCoverageSummary gate

    @Test func noLinesProducesNilSummary() {
        #expect(multiCoverageSummary(lines: []) == nil)
    }

    @Test func onlyUndatedLinesProducesNilSummary() {
        // Legacy label+covered lines with no dates at all — the v3 passport
        // must fall back to the plain v2 ring rather than showing an empty
        // multi-line group.
        let lines = [CoverageLine(label: "Parts", covered: true), CoverageLine(label: "Labour", covered: true)]
        #expect(multiCoverageSummary(lines: lines) == nil)
    }

    @Test func oneDatedLineIsEnoughToProduceASummary() {
        let now = Date.now
        var line = CoverageLine(label: "Warranty", covered: true)
        line.endDate = daysFromNow(60, from: now)
        let summary = multiCoverageSummary(lines: [line], now: now)
        #expect(summary != nil)
        #expect(summary?.totalCount == 1)
    }

    // MARK: - Longest-live-line selection

    @Test func longestLiveLineSelectionAmongMixedDatedUndatedAndExpiredLines() throws {
        let now = Date.now
        var shortActive = CoverageLine(label: "Parts & labour", covered: true)
        shortActive.endDate = daysFromNow(90, from: now) // ~3 mo

        var longActive = CoverageLine(label: "Panel — extended warranty", covered: true)
        longActive.endDate = daysFromNow(660, from: now) // ~22 mo — the longest live line

        var expired = CoverageLine(label: "Return window", covered: false)
        expired.endDate = daysFromNow(-175, from: now)

        let undated = CoverageLine(label: "Accidental damage", covered: true) // no dates at all

        let lines = [shortActive, longActive, expired, undated]
        let summary = try #require(multiCoverageSummary(lines: lines, now: now))

        #expect(summary.totalCount == 4)
        #expect(summary.activeCount == 3) // shortActive, longActive, undated(covered=true)
        #expect(summary.expiredCount == 1) // expired
        #expect(summary.ringLine.line.label == "Panel — extended warranty")
        #expect(summary.nextToLapse?.line.label == "Parts & labour") // soonest-to-lapse active dated line
    }

    @Test func ringFallsBackToLatestExpiredLineWhenNoActiveDatedLineExists() throws {
        let now = Date.now
        var olderExpired = CoverageLine(label: "Return window", covered: false)
        olderExpired.endDate = daysFromNow(-200, from: now)

        var newerExpired = CoverageLine(label: "Warranty", covered: false)
        newerExpired.endDate = daysFromNow(-10, from: now)

        let summary = try #require(multiCoverageSummary(lines: [olderExpired, newerExpired], now: now))
        #expect(summary.ringLine.line.label == "Warranty") // the later of the two expiries
        #expect(summary.nextToLapse == nil) // nothing active to report as "next to lapse"
        #expect(summary.activeCount == 0)
        #expect(summary.expiredCount == 2)
    }

    // MARK: - CoverageReminders: identifier format

    @Test func coverageIdentifierFormat() {
        let id = UUID()
        #expect(CoverageReminders.identifier(recordID: id, lineIndex: 0, offsetDays: 14) == "coverage-\(id.uuidString)-0-14d")
        #expect(CoverageReminders.identifier(recordID: id, lineIndex: 3, offsetDays: 0) == "coverage-\(id.uuidString)-3-0d")
    }

    @Test func offsetsAreLeadTimeOnlyNoDayOfNudge() {
        // §6 coverage reminders discipline: the day-of (0) offset was
        // dropped — lead-time only, one reminder per line/cluster.
        #expect(CoverageReminders.offsets(leadDays: 14) == [14])
        #expect(CoverageReminders.offsets(leadDays: 0) == [0])
    }

    // MARK: - CoverageReminders: dedupe vs. the warranty single

    @Test func lineWithinSevenDaysOfWarrantyExpiryIsDuplicate() {
        let warrantyExpiry = Date.now
        let endDate = daysFromNow(6, from: warrantyExpiry)
        #expect(CoverageReminders.isDuplicateOfWarranty(endDate: endDate, warrantyExpiryDate: warrantyExpiry))
    }

    @Test func lineMoreThanSevenDaysFromWarrantyExpiryIsNotDuplicate() {
        let warrantyExpiry = Date.now
        let endDate = daysFromNow(8, from: warrantyExpiry)
        #expect(!CoverageReminders.isDuplicateOfWarranty(endDate: endDate, warrantyExpiryDate: warrantyExpiry))
    }

    @Test func noWarrantyExpiryNeverDedupes() {
        #expect(!CoverageReminders.isDuplicateOfWarranty(endDate: .now, warrantyExpiryDate: nil))
    }

    // MARK: - CoverageReminders: 7-day dedupe grouping

    @Test func linesWithinSevenDaysGroupTogether() {
        let now = Date.now
        let a = CoverageReminders.DatedLine(index: 0, label: "A", endDate: daysFromNow(0, from: now))
        let b = CoverageReminders.DatedLine(index: 1, label: "B", endDate: daysFromNow(7, from: now))
        let groups = CoverageReminders.groupByDeadlineProximity([a, b])
        #expect(groups.count == 1)
        #expect(groups[0].map(\.label).sorted() == ["A", "B"])
    }

    @Test func linesMoreThanSevenDaysApartStayInSeparateGroups() {
        let now = Date.now
        let a = CoverageReminders.DatedLine(index: 0, label: "A", endDate: daysFromNow(0, from: now))
        let b = CoverageReminders.DatedLine(index: 1, label: "B", endDate: daysFromNow(8, from: now))
        let groups = CoverageReminders.groupByDeadlineProximity([a, b])
        #expect(groups.count == 2)
    }

    @Test func chainGroupingLinksThroughAnIntermediateLine() {
        // A–B is 6 days, B–C is 6 days (12 total A–C) — all three must still
        // land in one group because grouping chains through neighbors, not a
        // single global threshold from the earliest line.
        let now = Date.now
        let a = CoverageReminders.DatedLine(index: 0, label: "A", endDate: daysFromNow(0, from: now))
        let b = CoverageReminders.DatedLine(index: 1, label: "B", endDate: daysFromNow(6, from: now))
        let c = CoverageReminders.DatedLine(index: 2, label: "C", endDate: daysFromNow(12, from: now))
        let groups = CoverageReminders.groupByDeadlineProximity([a, b, c])
        #expect(groups.count == 1)
        #expect(groups[0].count == 3)
    }

    @Test func groupsAreSortedByEndDateAndUnrelatedLinesRemainSeparate() {
        let now = Date.now
        let far = CoverageReminders.DatedLine(index: 0, label: "Far", endDate: daysFromNow(400, from: now))
        let near1 = CoverageReminders.DatedLine(index: 1, label: "Near1", endDate: daysFromNow(1, from: now))
        let near2 = CoverageReminders.DatedLine(index: 2, label: "Near2", endDate: daysFromNow(3, from: now))
        let groups = CoverageReminders.groupByDeadlineProximity([far, near1, near2])
        #expect(groups.count == 2)
        #expect(groups[0].map(\.label).sorted() == ["Near1", "Near2"])
        #expect(groups[1].map(\.label) == ["Far"])
    }
}
