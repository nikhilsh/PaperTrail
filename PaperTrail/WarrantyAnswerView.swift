import SwiftUI
import SwiftData

/// A confident one-glance "are you covered?" verdict for a single record.
struct WarrantyAnswerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allAttachments: [Attachment]
    let record: PurchaseRecord

    private var attachments: [Attachment] { allAttachments.filter { $0.recordID == record.id } }

    /// Lead word + emphasis word + tail. Emphasis is gold for covered/expiring,
    /// light-terra for lapsed (per brief: "emphasis word in gold or terra").
    private var verdict: (lead: String, emphasis: String, tone: Color) {
        switch record.warrantyStatus {
        case .active:        return ("Yes — you're ", "covered.", PT.goldHi)
        case .expiringSoon:  return ("Yes — but it's ", "expiring.", PT.goldHi)
        case .expired:       return ("No — it's ", "lapsed.", Color(hex: 0xEAB69C))
        case .unknown:       return ("No warranty ", "on file.", PT.txt3)
        }
    }

    /// Stamp verdict — covered/expiring read as "Under warranty" (sage), expired
    /// as "Out of warranty" (terra), matching the prototype.
    private var stamp: (text: String, tone: Color) {
        switch record.warrantyStatus {
        case .expired:  return ("Out of warranty", PT.terra)
        case .unknown:  return ("No warranty", PT.txt3)
        default:        return ("Under warranty", PT.sageDeep)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(record.displayProductName)
                    .ptMonoLabel(11, tracking: 2)
                    .foregroundStyle(PT.txt3)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                Text("\(Text(verdict.lead).foregroundStyle(PT.txt))\(Text(verdict.emphasis).italic().foregroundStyle(verdict.tone))")
                    .font(PTFont.serif(38, weight: 600))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                StampBadge(text: stamp.text, tone: stamp.tone)

                ringCard

                if !attachments.isEmpty {
                    ProofChips(attachments: attachments)
                }

                // BUILD_REVIEW B2: proof + actions sit right under the ring —
                // no dead bottom half — and the full dossier is one tap away.
                VStack(spacing: 10) {
                    NavigationLink {
                        RecordDetailView(record: record)
                    } label: {
                        Text("View full passport  →")
                    }
                    .buttonStyle(PTOutlineButtonStyle())

                    NavigationLink {
                        SupportView(record: record)
                    } label: {
                        Text("Something's wrong with it  →")
                    }
                    .buttonStyle(PTOutlineButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.bottom, 120)
        }
        .ptScreen()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
    }

    /// BUILD_REVIEW B2: the old horizontal bar-with-knob read as a slider
    /// and invited dragging. The blessed progress idiom here is the same
    /// coverage ring as the passport, with BOUGHT / TODAY / EXPIRES as
    /// ledger rows beneath — nothing on this card looks draggable.
    private var ringCard: some View {
        VStack(spacing: 16) {
            if let expiry = record.warrantyExpiryDate {
                let values = coverageRingValues(purchaseDate: record.purchaseDate, expiryDate: expiry)
                CoverageRing(
                    totalMonths: values.total,
                    monthsRemaining: values.remaining,
                    unitSuffix: values.unit.suffix,
                    caption: record.warrantyStatus == .expired ? "LAPSED" : "REMAINING",
                    diameter: 132
                )
            } else {
                Text("No warranty dates on file")
                    .font(PTFont.serif(18, weight: 500))
                    .foregroundStyle(PT.onPaper2)
                    .padding(.vertical, 8)
            }

            VStack(spacing: 0) {
                LedgerRow(key: "Bought", value: record.purchaseDate.map { PTDate.dayMonthYear.string(from: $0) } ?? "—")
                LedgerRow(key: "Today", value: PTDate.dayMonthYear.string(from: .now))
                LedgerRow(key: record.warrantyStatus == .expired ? "Expired" : "Expires",
                          value: record.warrantyExpiryDate.map { PTDate.dayMonthYear.string(from: $0) } ?? "—")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .paperCard(goldFold: true)
    }
}

// MARK: - Proof chips (shared)

/// Horizontal row of small "proof on file" chips for a record's attachments.
struct ProofChips: View {
    let attachments: [Attachment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Proof on file", tone: PT.txt3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        Chip(symbol: chipSymbol(attachment.type), text: attachment.type.rawValue)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipSymbol(_ type: AttachmentType) -> String {
        switch type {
        case .receipt: "receipt"
        case .warranty: "shield.lefthalf.filled"
        case .invoice: "doc.text"
        case .other: "doc"
        }
    }
}

#Preview {
    NavigationStack { Text("Requires SwiftData context") }
        .environmentObject(CloudImageSyncManager.shared)
}
