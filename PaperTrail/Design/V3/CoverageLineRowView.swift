import SwiftUI

// MARK: - CoverageLineRowView (docs/design-v3/V3_BRIEF.md §2, `PaperTrail v3
// Screens.html` V3-2 `.covline`)
//
// One compact row in the multi-coverage passport's line list: bold label ·
// mono months-left (or "closed <date>" once lapsed) · sub "kind · to <date>
// · scope" · 4pt mini progress bar. Expired lines stay visible, struck
// through, with no sub-line and no bar — matching the mock's `.covline.dead`
// exactly.

struct CoverageLineRowView: View {
    let row: CoverageLineRowInfo

    private var line: CoverageLine { row.line }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.label)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(row.isActive ? PT.txt : PT.txt3)
                    .strikethrough(!row.isActive)
                Spacer(minLength: 8)
                Text(monoTrailingText)
                    .font(PTFont.mono(11.5, medium: true))
                    .foregroundStyle(PT.txt2)
            }

            if row.isActive, let sub {
                Text(sub)
                    .font(.system(size: 11.5))
                    .foregroundStyle(PT.txt3)
            }

            if row.isActive, let values = row.values {
                progressBar(fraction: fraction(for: values))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    /// "N mo left" / "N d left" while active; "closed <date>" once lapsed;
    /// "Covered" / "Not covered" for lines with no tracked `endDate` at all
    /// (pre-v3 lines, or v3 lines the user never dated).
    private var monoTrailingText: String {
        if let values = row.values {
            if row.isActive {
                return "\(values.remaining) \(values.unit.suffix) left"
            }
            if let endDate = line.endDate {
                return "closed \(PTDate.dayMonthYear.string(from: endDate))"
            }
        }
        return line.covered ? "Covered" : "Not covered"
    }

    /// "<kind> · to <date> · <scope>" — segments present only when the
    /// underlying field is set, joined with " · ". `kind` stands in for the
    /// mock's provider name ("Samsung", "Manufacturer") since `CoverageLine`
    /// has no separate provider field (V3_BRIEF §2 doesn't add one).
    private var sub: String? {
        guard let endDate = line.endDate else { return nil }
        var parts: [String] = []
        if let kindLabel = line.kindEnum?.label { parts.append(kindLabel) }
        parts.append("to \(PTDate.dayMonthYear.string(from: endDate))")
        if let scope = line.coveredItems, !scope.isEmpty {
            parts.append(scope.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private func fraction(for values: CoverageRingValues) -> CGFloat {
        guard values.total > 0 else { return 0 }
        return CGFloat(max(0, min(1, Double(values.remaining) / Double(values.total))))
    }

    private func progressBar(fraction: CGFloat) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                PT.sage
                    .frame(width: geo.size.width * fraction)
                PT.hair
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

#Preview("CoverageLineRowView") {
    VStack(spacing: 0) {
        CoverageLineRowView(row: CoverageLineRowInfo(
            index: 0,
            line: CoverageLine(label: "Panel — extended warranty", covered: true, startDate: nil, endDate: Calendar.current.date(byAdding: .month, value: 22, to: .now), kind: "extended", coveredItems: ["Panel defects only"]),
            isActive: true,
            values: CoverageRingValues(total: 36, remaining: 22, unit: .months)
        ))
        CoverageLineRowView(row: CoverageLineRowInfo(
            index: 1,
            line: CoverageLine(label: "Return window", covered: false, startDate: nil, endDate: Calendar.current.date(byAdding: .day, value: -175, to: .now), kind: nil, coveredItems: nil),
            isActive: false,
            values: CoverageRingValues(total: 30, remaining: 0, unit: .days)
        ))
    }
    .background(PT.inkCardDark)
    .padding(24)
    .background(PT.inkCanvas)
}
