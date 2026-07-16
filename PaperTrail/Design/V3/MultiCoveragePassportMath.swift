import Foundation

// MARK: - MultiCoveragePassportMath (docs/design-v3/V3_BRIEF.md §2, `multiCoverage`)
//
// Pure, nonisolated helpers for the multi-line Coverage Passport — mirrors
// `CoveragePassportMath.swift`'s shape (no SwiftUI, no `Date.now` default
// baked in past the call site) so this is trivially testable off the main
// actor. `RecordDetailView` is the only caller.

/// One coverage line reduced to what the passport row needs to render, plus
/// the index into `PurchaseRecord.coverageLines` it came from (rows need this
/// for the reminder-identifier / delete-line wiring elsewhere).
nonisolated struct CoverageLineRowInfo: Equatable, Identifiable {
    var id: Int { index }
    let index: Int
    let line: CoverageLine
    let isActive: Bool
    /// Ring-style total/remaining span for this line, in whichever unit reads
    /// best — `nil` when the line has no `endDate` to measure against.
    let values: CoverageRingValues?
}

/// Summary shown beside the passport ring and driving which line's span the
/// ring itself displays (V3_BRIEF §2: "ring shows the LONGEST live line").
nonisolated struct MultiCoverageSummary: Equatable {
    let totalCount: Int
    let activeCount: Int
    let expiredCount: Int
    /// The row info for the line the ring displays — the active line with the
    /// farthest-out `endDate`, or (if every dated line has already lapsed)
    /// the dated line with the overall farthest `endDate`, so the ring still
    /// has something to show rather than going blank.
    let ringLine: CoverageLineRowInfo
    /// Soonest-to-lapse *active* dated line, for "Next to lapse: <label>,
    /// <date>" — `nil` when no active line has a tracked expiry (e.g. every
    /// dated line already expired).
    let nextToLapse: CoverageLineRowInfo?
    /// Every line, dated or not, in original array order — the passport's
    /// compact-row list iterates this so nothing the user entered disappears
    /// just because it lacks dates.
    let rows: [CoverageLineRowInfo]
}

/// Builds the multi-coverage summary for `lines`, or `nil` when fewer than
/// one line carries a date (V3_BRIEF §2's gate: "record has ≥1 coverage line
/// with dates" — otherwise the caller falls back to the existing single-ring
/// v2 passport).
nonisolated func multiCoverageSummary(lines: [CoverageLine], now: Date = .now) -> MultiCoverageSummary? {
    let rows: [CoverageLineRowInfo] = lines.enumerated().map { index, line in
        let values = line.endDate.map { end in
            coverageRingValues(purchaseDate: line.startDate, expiryDate: end, now: now)
        }
        return CoverageLineRowInfo(index: index, line: line, isActive: line.isActive(now: now), values: values)
    }

    let dated = rows.filter { $0.line.endDate != nil }
    guard !dated.isEmpty else { return nil }

    let activeDated = dated.filter(\.isActive)
    let ringLine: CoverageLineRowInfo
    if let longestActive = activeDated.max(by: { $0.line.endDate! < $1.line.endDate! }) {
        ringLine = longestActive
    } else {
        // Every dated line has lapsed — fall back to whichever expired latest
        // so the ring reads "0 remaining" against a real span instead of
        // picking arbitrarily.
        ringLine = dated.max(by: { $0.line.endDate! < $1.line.endDate! })!
    }

    let nextToLapse = activeDated.min { $0.line.endDate! < $1.line.endDate! }

    let activeCount = rows.filter(\.isActive).count
    return MultiCoverageSummary(
        totalCount: rows.count,
        activeCount: activeCount,
        expiredCount: rows.count - activeCount,
        ringLine: ringLine,
        nextToLapse: nextToLapse,
        rows: rows
    )
}
