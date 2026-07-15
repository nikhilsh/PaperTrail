import SwiftUI
import SwiftData

/// "Fix-it" list — every record that isn't claim-ready yet (Proof Score < 90),
/// surfaced highest-value-first so the records most worth backing with proof
/// show up before low-value ones. Reached from Settings → Your library.
struct ProofFixListView: View {
    @Query(sort: \PurchaseRecord.updatedAt, order: .reverse) private var records: [PurchaseRecord]
    @Query private var allAttachments: [Attachment]

    private func attachments(for record: PurchaseRecord) -> [Attachment] {
        allAttachments.filter { $0.recordID == record.id }
    }

    private func score(for record: PurchaseRecord) -> ProofScore {
        let snapshot = ProofScoreSnapshot(
            hasAttachment: !attachments(for: record).isEmpty,
            purchaseDate: record.purchaseDate,
            amount: record.amount,
            warrantyExpiryDate: record.warrantyExpiryDate,
            serialNumber: record.serialNumber,
            productImageAttachmentID: record.productImageAttachmentID
        )
        return ProofScore(snapshot: snapshot)
    }

    /// Records needing proof, sorted by amount descending (records with no
    /// amount sort last), then by score ascending (least complete first).
    private var rows: [(record: PurchaseRecord, score: ProofScore)] {
        records
            .map { (record: $0, score: score(for: $0)) }
            .filter { $0.score.score < 90 }
            .sorted { lhs, rhs in
                switch (lhs.record.amount, rhs.record.amount) {
                case let (l?, r?) where l != r:
                    return l > r
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                default:
                    return lhs.score.score < rhs.score.score
                }
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Proof completeness")
                    .font(PTFont.serif(30, weight: 600))
                    .foregroundStyle(PT.txt)

                if rows.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: PT.Metric.cardGap) {
                        ForEach(rows, id: \.record.id) { row in
                            NavigationLink {
                                RecordDetailView(record: row.record)
                            } label: {
                                ProofFixRow(record: row.record, score: row.score)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .ptScreen()
        .navigationTitle("Proof completeness")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 30))
                .foregroundStyle(PT.sageDeep)
            Text("Every record is claim-ready.")
                .font(.system(size: 14))
                .foregroundStyle(PT.txt3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Row

private struct ProofFixRow: View {
    let record: PurchaseRecord
    let score: ProofScore

    private var tone: Color {
        switch score.level {
        case .claimReady: PT.sageDeep
        case .nearlyThere: PT.amber
        case .needsProof: PT.terra
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.productName)
                    .font(PTFont.serif(16, weight: 500))
                    .foregroundStyle(PT.txt)
                    .lineLimit(1)
                if let topMissing = score.missingItems.first {
                    Text(topMissing)
                        .font(PTFont.mono(10))
                        .foregroundStyle(PT.txt3)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(record.formattedAmount ?? "—")
                    .font(PTFont.mono(12, medium: true))
                    .foregroundStyle(PT.txt2)
                Text("\(score.score)")
                    .ptMonoLabel(10, tracking: 1.2)
                    .foregroundStyle(tone)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PT.txt3)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color(hex: 0xE7DCC4, alpha: 0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }
}

#Preview {
    NavigationStack {
        ProofFixListView()
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
