import SwiftUI

// MARK: - LedgerRow (docs/design-v2/DESIGN_LANGUAGE.md §5 S3)
//
// Mono key … dotted leader … value — for dense, read-only lists (receipt
// lines, ledger-style detail rows).

struct LedgerRow: View {
    let key: String
    let value: String
    var onPaper: Bool = true

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(key.uppercased())
                .font(PTFont.mono(11))
                .foregroundStyle(onPaper ? PT.onPaper2 : PT.txt2)
                .lineLimit(1)
                .layoutPriority(1)
            DottedLeader(color: onPaper ? Color(hex: 0x211C12, alpha: 0.18) : PT.hair)
                .frame(height: 1)
            Text(value)
                .font(PTFont.mono(11.5, medium: true))
                .foregroundStyle(onPaper ? PT.onPaper : PT.txt)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.vertical, 5)
    }
}

private struct DottedLeader: View {
    var color: Color

    var body: some View {
        GeometryReader { geo in
            Path { p in
                let y = geo.size.height / 2
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: geo.size.width, y: y))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 3]))
        }
    }
}

#Preview("LedgerRow") {
    VStack(spacing: 0) {
        LedgerRow(key: "Serial", value: "SN-4X2K-88103")
        LedgerRow(key: "Model", value: "QA55S90DAKXXS")
        LedgerRow(key: "Bought", value: "8 Jan 2026")
    }
    .padding(20)
    .paperCard(goldFold: false)
    .padding(24)
    .ptScreen()
}
