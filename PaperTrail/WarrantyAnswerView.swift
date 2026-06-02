import SwiftUI
import SwiftData

/// A confident one-glance "are you covered?" verdict for a single record.
struct WarrantyAnswerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allAttachments: [Attachment]
    let record: PurchaseRecord

    private var warranty: PTWarranty { PTWarranty(record: record) }
    private var attachments: [Attachment] { allAttachments.filter { $0.recordID == record.id } }

    /// Lead word + emphasis word + tail, with the emphasis tinted by status.
    private var verdict: (lead: String, emphasis: String, tone: Color) {
        switch record.warrantyStatus {
        case .active:        return ("Yes — you're ", "covered.", PT.gold)
        case .expiringSoon:  return ("Yes — but it's ", "expiring.", PT.amber)
        case .expired:       return ("No — it's ", "lapsed.", PT.terra)
        case .unknown:       return ("No warranty ", "on file.", PT.txt3)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(record.productName)
                    .ptMonoLabel(11, tracking: 2)
                    .foregroundStyle(PT.txt3)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                (Text(verdict.lead).foregroundStyle(PT.txt)
                 + Text(verdict.emphasis).italic().foregroundStyle(verdict.tone))
                    .font(PTFont.serif(38, weight: 600))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                StampBadge(text: warranty.stampText, tone: verdict.tone)

                timelineCard

                if !attachments.isEmpty {
                    ProofChips(attachments: attachments)
                }

                NavigationLink {
                    SupportView(record: record)
                } label: {
                    Text("Something's wrong with it  →")
                }
                .buttonStyle(PTOutlineButtonStyle())
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

    private var timelineCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(record.warrantyStatus == .expired ? "Lapsed" : warranty.remainingShort.replacingOccurrences(of: " left", with: ""))
                    .font(PTFont.serif(40, weight: 600))
                    .foregroundStyle(PT.onPaper)
                Text(record.warrantyStatus == .expired ? "out of warranty" : "remaining")
                    .ptMonoLabel(9.5, tracking: 1.8)
                    .foregroundStyle(PT.onPaper3)
            }

            // Timeline: purchase ── Today ── expiry
            VStack(spacing: 6) {
                GeometryReader { geo in
                    let elapsed = 1 - warranty.progressRemaining
                    ZStack(alignment: .leading) {
                        Capsule().fill(PT.onPaperHair).frame(height: 5)
                        Capsule()
                            .fill(LinearGradient(colors: [warranty.status.tone.opacity(0.7), warranty.status.tone],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, min(1, elapsed)) * geo.size.width, height: 5)
                        Circle()
                            .fill(PT.onPaper)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(PT.paper, lineWidth: 2))
                            .offset(x: max(0, min(1, elapsed)) * geo.size.width - 5.5)
                    }
                }
                .frame(height: 12)

                HStack {
                    endpoint(label: "Bought", value: record.purchaseDate)
                    Spacer()
                    Text("Today")
                        .ptMonoLabel(8.5, tracking: 1.2)
                        .foregroundStyle(PT.onPaper2)
                    Spacer()
                    endpoint(label: "Expires", value: record.warrantyExpiryDate, trailing: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .paperCard(goldFold: true)
    }

    private func endpoint(label: String, value: Date?, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(label)
                .ptMonoLabel(8, tracking: 1.2)
                .foregroundStyle(PT.onPaper3)
            Text(value.map { PTDate.dayMonthYear.string(from: $0) } ?? "—")
                .font(PTFont.mono(10))
                .foregroundStyle(PT.onPaper2)
        }
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
