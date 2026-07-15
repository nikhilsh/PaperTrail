import SwiftUI
import SwiftData
import MessageUI

/// Whether the claim packet is worth offering for a record. Centralized so every
/// entry point (Detail share icon, Support step 1) gates the same way: a packet
/// with no proof images is just metadata, useless for an actual claim.
enum ClaimPacketAvailability {
    static func isOffered(attachmentCount: Int) -> Bool { attachmentCount > 0 }
}

/// The payoff (§9): one shareable PDF with everything a repair, retailer, or
/// insurer asks for. Reached from Detail's share icon, the warranty answer's
/// "Something's wrong with it", and Support step 1.
struct ClaimPacketView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @Query private var allAttachments: [Attachment]
    let record: PurchaseRecord

    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var isGenerating = false
    @State private var showMailComposer = false
    @State private var mailAttachment: URL?

    private var attachments: [Attachment] { allAttachments.filter { $0.recordID == record.id } }
    private var docNumber: String { ClaimPacketPDF.documentNumber(for: record) }

    private var proofThumbs: [(Attachment, String)] {
        var result: [(Attachment, String)] = []
        let productID = record.productImageAttachmentID
        if let receipt = attachments.first(where: { $0.type == .receipt && $0.id != productID }) { result.append((receipt, "Receipt")) }
        if let warrantyDoc = attachments.first(where: { $0.type == .warranty && $0.id != productID }) { result.append((warrantyDoc, "Warranty")) }
        if let id = productID, let product = attachments.first(where: { $0.id == id }) { result.append((product, "Product")) }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claim packet")
                        .font(PTFont.serif(32, weight: 600))
                        .foregroundStyle(PT.txt)
                    Text("One PDF with everything a repair, retailer, or insurer asks for — assembled and ready to send.")
                        .font(.system(size: 14))
                        .foregroundStyle(PT.txt2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                documentCard

                VStack(spacing: 10) {
                    Button { Task { await share() } } label: {
                        HStack(spacing: 8) {
                            if isGenerating { ProgressView().tint(PT.inkStamp) }
                            Text(isGenerating ? "Preparing…" : "Share claim packet · PDF")
                        }
                    }
                    .buttonStyle(PTGoldButtonStyle())
                    .disabled(isGenerating)

                    Button { Task { await emailToSelf() } } label: {
                        Text("Email a copy to myself")
                    }
                    .buttonStyle(PTOutlineButtonStyle())
                    .disabled(isGenerating)
                }
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.bottom, 120)
        }
        .ptScreen()
        .task {
            // Pull any proof images that haven't landed locally so the PDF is complete.
            for att in attachments where att.image == nil {
                await cloudImageSync.download(attachmentID: att.id, localFilename: att.localFilename)
            }
        }
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
        .sheet(isPresented: $showShareSheet) {
            if let shareURL { ShareSheetView(activityItems: [shareURL]) }
        }
        .sheet(isPresented: $showMailComposer) {
            if let mailAttachment {
                MailComposeView(
                    recipients: [],
                    subject: "Claim packet · \(record.productName)",
                    body: "Attached is the proof-of-purchase & warranty claim packet for \(record.productName) (\(docNumber)).",
                    attachmentURL: mailAttachment
                )
            }
        }
    }

    // MARK: Document preview card

    private var documentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PAPERTRAIL")
                    .ptMonoLabel(10, tracking: 3.5)
                    .foregroundStyle(PT.goldDeep)
                Spacer()
                Text(docNumber)
                    .font(PTFont.mono(10))
                    .foregroundStyle(PT.onPaper3)
            }
            Text("PROOF OF PURCHASE & WARRANTY")
                .font(PTFont.mono(8.5))
                .tracking(1.2)
                .foregroundStyle(PT.onPaper3)
                .padding(.top, 8)

            Text(record.productName)
                .font(PTFont.serif(24, weight: 600))
                .foregroundStyle(PT.onPaper)
                .padding(.top, 12)

            GoldRule().padding(.vertical, 14)

            VStack(spacing: 10) {
                kvLine("Model", record.productName)
                if let serial = record.serialNumber, !serial.isEmpty { kvLine("Serial no.", serial, mono: true) }
                kvLine("Purchased", purchasedText)
                kvLine("Price paid", record.formattedAmount ?? "—", mono: true)
                kvLine("Warranty", record.warrantyExpiryDate.map { "Until \(PTDate.dayMonthYear.string(from: $0))" } ?? "Not on file")
                if let coverage = record.coverageSummary, !coverage.isEmpty { kvLine("Covers", coverage) }
                kvLine("Status", record.warrantyStatus.label, valueColor: record.warrantyStatus.tone)
            }

            if !proofThumbs.isEmpty {
                Text("ATTACHED PROOF")
                    .font(PTFont.mono(8.5))
                    .tracking(1.2)
                    .foregroundStyle(PT.onPaper3)
                    .padding(.top, 18)
                HStack(spacing: 10) {
                    ForEach(proofThumbs, id: \.0.id) { (attachment, label) in
                        VStack(spacing: 6) {
                            Group {
                                if let image = attachment.image {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    ZStack { PT.paperBottom; Image(systemName: "photo").foregroundStyle(PT.onPaper3) }
                                }
                            }
                            .frame(width: 70, height: 92)
                            .clipShape(DogEarShape(radius: 8, ear: 12))
                            .overlay(DogEarShape(radius: 8, ear: 12).stroke(PT.onPaperHair, lineWidth: 1))
                            Text(label)
                                .font(PTFont.mono(8))
                                .textCase(.uppercase)
                                .foregroundStyle(PT.onPaper2)
                        }
                    }
                }
                .padding(.top, 8)
            }

            Rectangle().fill(PT.onPaperHair).frame(height: 1).padding(.top, 16)
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 10))
                    .foregroundStyle(PT.onPaper3)
                Text(tamperLine)
                    .font(PTFont.mono(8.5))
                    .foregroundStyle(PT.onPaper3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: true)
    }

    private func kvLine(_ label: String, _ value: String, mono: Bool = false, valueColor: Color = PT.onPaper) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(PTFont.mono(8.5))
                .tracking(0.8)
                .foregroundStyle(PT.onPaper3)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(mono ? PTFont.mono(12, medium: true) : PTFont.serif(14, weight: 500))
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }

    private var purchasedText: String {
        [record.purchaseDate.map { PTDate.dayMonthYear.string(from: $0) }, record.merchantName]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var tamperLine: String {
        if let captured = attachments.map(\.createdAt).min() {
            return "Captured \(PTDate.dayMonthYear.string(from: captured)) · original kept on file since purchase."
        }
        return "Original proof kept on file since purchase."
    }

    // MARK: Actions

    @MainActor
    private func makePDF() async -> URL? {
        // Make sure proof images are present locally before rendering.
        isGenerating = true
        defer { isGenerating = false }
        let url = ClaimPacketPDF.generate(record: record, attachments: attachments)
        // Delight moment: the claim-packet export completed, never on failure.
        if url != nil {
            ReviewPrompter.shared.claimPacketExported()
        }
        return url
    }

    private func share() async {
        guard let url = await makePDF() else { return }
        shareURL = url
        showShareSheet = true
    }

    private func emailToSelf() async {
        guard let url = await makePDF() else { return }
        if MFMailComposeViewController.canSendMail() {
            mailAttachment = url
            showMailComposer = true
        } else {
            // No Mail account configured — fall back to the share sheet.
            shareURL = url
            showShareSheet = true
        }
    }
}

/// Minimal MFMailComposeViewController wrapper for "Email a copy to myself".
struct MailComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    let attachmentURL: URL

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let data = try? Data(contentsOf: attachmentURL) {
            vc.addAttachmentData(data, mimeType: "application/pdf", fileName: attachmentURL.lastPathComponent)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                  didFinishWith result: MFMailComposeResult,
                                  error: Error?) {
            dismiss()
        }
    }
}
