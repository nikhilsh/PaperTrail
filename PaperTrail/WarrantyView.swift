import SwiftUI
import SwiftData

/// The "am I covered?" dashboard. Backed entirely by `PurchaseRecord.warrantyStatus`.
struct WarrantyView: View {
    @Query private var records: [PurchaseRecord]

    /// Expired + expiring, sorted by risk: expired first, then soonest-expiring.
    private var needsAttention: [PurchaseRecord] {
        records
            .filter { $0.warrantyStatus == .expired || $0.warrantyStatus == .expiringSoon }
            .sorted { lhs, rhs in
                func rank(_ r: PurchaseRecord) -> Int { r.warrantyStatus == .expired ? 0 : 1 }
                if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
                return (lhs.warrantyExpiryDate ?? .distantFuture) < (rhs.warrantyExpiryDate ?? .distantFuture)
            }
    }

    private var restingEasy: [PurchaseRecord] {
        records
            .filter { $0.warrantyStatus == .active }
            .sorted { ($0.warrantyExpiryDate ?? .distantFuture) < ($1.warrantyExpiryDate ?? .distantFuture) }
    }

    private var hasWarranties: Bool {
        records.contains { $0.warrantyExpiryDate != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Warranty")
                    .font(PTFont.serif(34, weight: 600))
                    .foregroundStyle(PT.txt)
                    .padding(.top, 8)

                if !hasWarranties {
                    emptyState
                } else {
                    if !needsAttention.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionLabel(text: "Needs attention", tone: PT.terra)
                            ForEach(needsAttention) { record in
                                AttentionCard(record: record)
                            }
                        }
                    }

                    if !restingEasy.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionLabel(text: "Resting easy", tone: PT.sage)
                            RestingEasyCard(records: restingEasy)
                        }
                    }
                }
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.bottom, 120)
        }
        .ptScreen()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(PT.txt3)
            Text("No warranties tracked yet.")
                .font(PTFont.serif(18, weight: 500))
                .foregroundStyle(PT.txt2)
            Text("Add a warranty expiry to a record and it\nwill show up here.")
                .font(.system(size: 13))
                .foregroundStyle(PT.txt3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Needs-attention card

private struct AttentionCard: View {
    let record: PurchaseRecord
    private var warranty: PTWarranty { PTWarranty(record: record) }

    private var stampTone: Color {
        record.warrantyStatus == .expired ? PT.terra : PT.amber
    }

    private var stampText: String {
        if record.warrantyStatus == .expired { return "Expired" }
        return warranty.remainingShort   // e.g. "28 days left"
    }

    /// "9 months left" / "Lapsed 4 months ago" — the human warranty line.
    private var leftLine: String {
        guard let expiry = record.warrantyExpiryDate else { return "No warranty" }
        if record.warrantyStatus == .expired {
            return "Lapsed \(PTWarranty.relativePast(expiry))"
        }
        return warranty.remainingShort
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                GlyphTile(symbol: warranty.glyph, size: 36, onPaper: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.productName)
                        .font(PTFont.serif(16, weight: 600))
                        .foregroundStyle(PT.onPaper)
                        .lineLimit(2)
                    Text(leftLine)
                        .font(PTFont.mono(10.5))
                        .foregroundStyle(PT.onPaper2)
                }
                Spacer(minLength: 8)
                StampBadge(text: stampText, tone: stampTone, compact: true)
            }

            WarrantyProgressBar(progress: warranty.progressElapsed, tone: warranty.status.tone)

            if record.warrantyStatus == .expired {
                NavigationLink {
                    SupportView(record: record)
                } label: {
                    Text("Get support")
                }
                .buttonStyle(PTDarkButtonStyle(fullWidth: true))
            } else {
                NavigationLink {
                    WarrantyAnswerView(record: record)
                } label: {
                    Text("View warranty")
                }
                .buttonStyle(PTDarkButtonStyle(fullWidth: true))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: true)
    }
}

// MARK: - Resting-easy card

private struct RestingEasyCard: View {
    let records: [PurchaseRecord]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                let warranty = PTWarranty(record: record)
                NavigationLink {
                    WarrantyAnswerView(record: record)
                } label: {
                    HStack(spacing: 12) {
                        GlyphTile(symbol: warranty.glyph, size: 34, onPaper: true)
                        Text(record.productName)
                            .font(PTFont.serif(16, weight: 500))
                            .foregroundStyle(PT.onPaper)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(warranty.remainingShort)
                            .font(PTFont.mono(10.5, medium: true))
                            .foregroundStyle(PT.sageDeep)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < records.count - 1 {
                    Rectangle().fill(PT.onPaperHair).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: false)
    }
}

#Preview {
    NavigationStack { WarrantyView() }
        .environmentObject(CloudImageSyncManager.shared)
        .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
