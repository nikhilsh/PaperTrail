import SwiftUI
import SwiftData
import PhotosUI

struct RecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @Query private var allAttachments: [Attachment]
    @Bindable var record: PurchaseRecord

    @State private var showDeleteConfirmation = false
    @State private var selectedImageFilename: SelectedFilename?
    @State private var showScanner = false
    @State private var isAddingProof = false
    @State private var productPhotoItem: PhotosPickerItem?
    @State private var isAddingProductPhoto = false
    @State private var toastMessage: String?

    private let scanningService = ScanningService()

    private var attachments: [Attachment] {
        allAttachments.filter { $0.recordID == record.id }
    }

    /// The attachment flagged as the product photo (§8), if any.
    private var productAttachment: Attachment? {
        guard let id = record.productImageAttachmentID else { return nil }
        return attachments.first { $0.id == id }
    }

    /// Receipt / warranty / invoice / other docs — everything except the product photo.
    private var documentAttachments: [Attachment] {
        attachments.filter { $0.id != record.productImageAttachmentID }
    }

    private var warranty: PTWarranty { PTWarranty(record: record) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard

                detailsCard

                if record.warrantyExpiryDate != nil {
                    warrantyBlock
                }

                proofSection

                supportCard

                if let notes = record.notes, !notes.isEmpty {
                    notesCard(notes)
                }

                Button("Delete record", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .font(PTFont.mono(11, medium: true))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(PT.terra)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .padding(.horizontal, PT.Metric.detailPad)
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
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    // Share now routes to the Claim Packet (§9) — a formatted PDF
                    // — superseding the old raw proof-bundle share.
                    NavigationLink {
                        ClaimPacketView(record: record)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }

                    NavigationLink {
                        EditRecordView(record: record)
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
                .font(.system(size: 16))
                .foregroundStyle(PT.txt2)
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView(
                onScanComplete: { images in
                    showScanner = false
                    Task { await addProof(images: images) }
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .confirmationDialog("Delete this record?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteRecord() }
        } message: {
            Text("This will permanently remove the record and its attachments.")
        }
        .fullScreenCover(item: $selectedImageFilename) { selected in
            ImageViewerView(filename: selected.value, attachmentID: selected.attachmentID)
        }
        .photosPicker(isPresented: $showProductPhotoPicker, selection: $productPhotoItem, matching: .images)
        .onChange(of: productPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await addProductPhoto(item: newItem) }
            productPhotoItem = nil
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(PTFont.mono(11, medium: true))
                    .foregroundStyle(PT.txt)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(PT.inkStamp, in: Capsule())
                    .overlay(Capsule().stroke(PT.goldDeep, lineWidth: 1))
                    .padding(.bottom, 140)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    @State private var showProductPhotoPicker = false

    // MARK: Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                GlyphTile(symbol: warranty.glyph, size: 52, onPaper: true)
                Spacer()
                if record.warrantyExpiryDate != nil {
                    StampBadge(text: warranty.stampText, tone: warranty.status.tone)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.productName)
                    .font(PTFont.serif(26, weight: 600))
                    .foregroundStyle(PT.onPaper)
                    .lineLimit(3)
                if let meta = modelRoomLine {
                    Text(meta)
                        .font(PTFont.mono(11))
                        .tracking(0.6)
                        .foregroundStyle(PT.onPaper3)
                }
            }

            Rectangle().fill(PT.onPaperHair).frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                heroStat(label: "Paid", value: record.formattedAmount ?? "—", mono: true)
                heroStat(label: "From", value: record.merchantName ?? "—", mono: false)
                heroStat(label: "Bought", value: record.purchaseDate.map { PTDate.dayMonthYear.string(from: $0) } ?? "—", mono: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: true)
    }

    private var modelRoomLine: String? {
        var parts: [String] = []
        if let category = record.category, !category.isEmpty { parts.append(category) }
        if !record.tags.isEmpty { parts.append(record.tags.joined(separator: " · ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func heroStat(label: String, value: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .ptMonoLabel(8.5, tracking: 1.5)
                .foregroundStyle(PT.onPaper3)
            Text(value)
                .font(mono ? PTFont.mono(13, medium: true) : PTFont.serif(15, weight: 500))
                .foregroundStyle(PT.onPaper)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Details card (§8 — serial / coverage / registration)

    private var brand: String {
        record.supportInfo?.providerName ?? record.merchantName ?? "the manufacturer"
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Details", tone: PT.txt3)

            detailRow(label: "Model", value: record.productName)

            if let serial = record.serialNumber, !serial.isEmpty {
                serialRow(serial)
            }

            if let coverage = record.coverageSummary, !coverage.isEmpty {
                detailRow(label: "Covers", value: coverage)
            }

            registrationRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xE7DCC4, alpha: 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(PT.txt3)
            Spacer(minLength: 12)
            Text(value)
                .font(PTFont.serif(15, weight: 500))
                .foregroundStyle(PT.txt)
                .multilineTextAlignment(.trailing)
        }
    }

    private func serialRow(_ serial: String) -> some View {
        Button {
            UIPasteboard.general.string = serial
            showToast("Serial number copied")
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text("Serial no.")
                    .font(.system(size: 13))
                    .foregroundStyle(PT.txt3)
                Spacer(minLength: 12)
                Text(serial)
                    .font(PTFont.mono(13, medium: true))
                    .foregroundStyle(PT.txt)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(PT.gold)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var registrationRow: some View {
        Rectangle().fill(PT.hair).frame(height: 1)
        if record.isRegistered {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(PT.sage)
                Text("Registered with \(brand) — full coverage active")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(hex: 0xCFE0B0))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(PT.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not registered yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xF0D49A))
                    Text("Register to activate full coverage")
                        .font(.system(size: 11.5))
                        .foregroundStyle(PT.txt3)
                }
                Spacer(minLength: 8)
                Button { registerProduct() } label: {
                    Text("Register")
                }
                .buttonStyle(PTDarkButtonStyle())
            }
        }
    }

    // MARK: Warranty block

    private var warrantyBlock: some View {
        NavigationLink {
            WarrantyAnswerView(record: record)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "Warranty", tone: warranty.status.tone)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PT.txt3)
                }
                Text(warranty.pillText)
                    .font(PTFont.serif(20, weight: 600, italic: true))
                    .foregroundStyle(PT.txt)
                WarrantyProgressBar(progress: warranty.progressElapsed, tone: warranty.status.tone, onPaper: false)
                HStack {
                    Text("\(record.purchaseDate.map { PTDate.dayMonthYear.string(from: $0) } ?? "—") — purchased")
                        .font(PTFont.mono(10))
                        .foregroundStyle(PT.txt3)
                    Spacer()
                    Text("\(record.warrantyExpiryDate.map { PTDate.dayMonthYear.string(from: $0) } ?? "—") — \(record.warrantyStatus == .expired ? "expired" : "expires")")
                        .font(PTFont.mono(10))
                        .foregroundStyle(PT.txt3)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(warranty.status.tone.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(warranty.status.tone.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Proof

    private var proofSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Proof on file", tone: PT.txt3)
                Spacer()
                if !attachments.isEmpty {
                    Text("\(attachments.count) document\(attachments.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(PT.txt3)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(documentAttachments) { attachment in
                        VStack(spacing: 8) {
                            Button {
                                openAttachment(attachment)
                            } label: {
                                ProofThumbnail(attachment: attachment)
                                    .overlay(alignment: .bottomTrailing) {
                                        CloudImageStatusOverlay(
                                            attachmentID: attachment.id,
                                            hasLocalImage: attachment.image != nil,
                                            syncManager: cloudImageSync
                                        )
                                    }
                            }
                            .buttonStyle(.plain)
                            HStack(spacing: 5) {
                                Image(systemName: proofGlyph(attachment.type))
                                    .font(.system(size: 10))
                                    .foregroundStyle(PT.gold)
                                Text(proofLabel(attachment.type))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(PT.txt2)
                            }
                        }
                    }

                    // Product photo — the third proof thumbnail (§8).
                    productProofSlot

                    VStack(spacing: 8) {
                        Button { showScanner = true } label: {
                            addProofTile
                        }
                        .buttonStyle(.plain)
                        Text(" ").font(.system(size: 10.5))
                    }
                }
            }
            .task {
                let missing = attachments.filter { $0.image == nil }
                for att in missing {
                    await cloudImageSync.download(attachmentID: att.id, localFilename: att.localFilename)
                }
            }
        }
    }

    private func proofGlyph(_ type: AttachmentType) -> String {
        switch type {
        case .receipt: "receipt"
        case .warranty: "shield.lefthalf.filled"
        case .invoice: "doc.text"
        case .other: "doc"
        }
    }

    private func proofLabel(_ type: AttachmentType) -> String {
        switch type {
        case .receipt: "Receipt"
        case .warranty: "Warranty card"
        case .invoice: "Invoice"
        case .other: "Document"
        }
    }

    private var addProofTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(PT.txt3)
            VStack(spacing: 6) {
                if isAddingProof {
                    ProgressView().tint(PT.txt2)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .regular))
                    Text("Add")
                        .ptMonoLabel(8.5, tracking: 1.2)
                }
            }
            .foregroundStyle(PT.txt2)
        }
        .frame(width: 78, height: 104)
    }

    @ViewBuilder
    private var productProofSlot: some View {
        if let productAttachment {
            VStack(spacing: 8) {
                Button { openAttachment(productAttachment) } label: {
                    ProofThumbnail(attachment: productAttachment)
                        .overlay(alignment: .bottomTrailing) {
                            CloudImageStatusOverlay(
                                attachmentID: productAttachment.id,
                                hasLocalImage: productAttachment.image != nil,
                                syncManager: cloudImageSync
                            )
                        }
                }
                .buttonStyle(.plain)
                HStack(spacing: 5) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 10))
                        .foregroundStyle(PT.gold)
                    Text("Product")
                        .font(.system(size: 10.5))
                        .foregroundStyle(PT.txt2)
                }
            }
        } else {
            VStack(spacing: 8) {
                Button { showProductPhotoPicker = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundStyle(PT.txt3)
                        VStack(spacing: 6) {
                            if isAddingProductPhoto {
                                ProgressView().tint(PT.txt2)
                            } else {
                                Image(systemName: "camera")
                                    .font(.system(size: 18, weight: .regular))
                                Text("Product")
                                    .ptMonoLabel(8.5, tracking: 1.2)
                            }
                        }
                        .foregroundStyle(PT.txt2)
                    }
                    .frame(width: 78, height: 104)
                }
                .buttonStyle(.plain)
                Text(" ").font(.system(size: 10.5))
            }
        }
    }

    // MARK: Support card

    private var supportCard: some View {
        NavigationLink {
            SupportView(record: record)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(text: "If it breaks", tone: PT.onPaper3)
                    Spacer()
                }
                if let support = record.supportInfo {
                    Text(support.providerName)
                        .font(PTFont.serif(18, weight: 600))
                        .foregroundStyle(PT.onPaper)
                    Text(support.phoneNumber)
                        .font(PTFont.mono(13, medium: true))
                        .foregroundStyle(PT.onPaper2)
                    if support.confidence == .verified {
                        label(symbol: "checkmark.seal.fill", text: "Verified from your receipt", tone: PT.sageDeep)
                    } else {
                        label(symbol: "questionmark.circle", text: "Best guess · looked up, not from your receipt.", tone: Color(hex: 0x9A7A33))
                    }
                } else {
                    Text("Get help finding support and proof for this item.")
                        .font(.system(size: 13))
                        .foregroundStyle(PT.onPaper2)
                }
                HStack {
                    Spacer()
                    Text("Get help  →")
                        .font(PTFont.mono(11, medium: true))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(PT.onPaper)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color(hex: 0x211C12, alpha: 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard(goldFold: false)
        }
        .buttonStyle(.plain)
    }

    private func label(symbol: String, text: String, tone: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(text).font(PTFont.mono(10))
        }
        .foregroundStyle(tone)
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Notes", tone: PT.txt3)
            Text(notes)
                .font(.system(size: 14))
                .foregroundStyle(PT.txt)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xE7DCC4, alpha: 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }

    // MARK: Actions

    private func openAttachment(_ attachment: Attachment) {
        if attachment.image != nil {
            selectedImageFilename = SelectedFilename(attachment.localFilename, attachmentID: attachment.id)
        } else {
            Task {
                let success = await cloudImageSync.download(attachmentID: attachment.id, localFilename: attachment.localFilename)
                if success {
                    selectedImageFilename = SelectedFilename(attachment.localFilename, attachmentID: attachment.id)
                }
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { if toastMessage == message { toastMessage = nil } }
        }
    }

    private func registerProduct() {
        let query = "\(brand) product registration"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.google.com/search?q=\(query)") {
            openURL(url)
        }
    }

    private func addProductPhoto(item: PhotosPickerItem) async {
        isAddingProductPhoto = true
        defer { isAddingProductPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let filename = ImageStorageManager.save(image) else { return }
        let attachment = Attachment(recordID: record.id, type: .other, localFilename: filename)
        modelContext.insert(attachment)
        record.productImageAttachmentID = attachment.id
        record.updatedAt = .now
        await cloudImageSync.upload(attachmentID: attachment.id, localFilename: filename)
        showToast("Product photo added")
    }

    private func addProof(images: [UIImage]) async {
        isAddingProof = true
        defer { isAddingProof = false }
        let learned = MerchantLearningService(modelContext: modelContext).learnedMerchantNames()
        let result = await scanningService.process(images: images, type: .other, learnedMerchants: learned)
        for attachment in result.attachments {
            attachment.recordID = record.id
            modelContext.insert(attachment)
        }
        record.updatedAt = .now
        let toUpload = result.attachments.map { AttachmentSyncInfo(id: $0.id, localFilename: $0.localFilename) }
        for info in toUpload {
            await cloudImageSync.upload(attachmentID: info.id, localFilename: info.localFilename)
        }
    }

    private func deleteRecord() {
        let attachmentIDs = attachments.map { $0.id }
        for attachment in attachments {
            ImageStorageManager.delete(attachment.localFilename)
            modelContext.delete(attachment)
        }
        NotificationManager.shared.removeWarrantyReminders(for: record)
        NotificationManager.shared.removeReturnWindowReminder(for: record)
        modelContext.delete(record)

        Task {
            for id in attachmentIDs {
                await cloudImageSync.delete(attachmentID: id)
            }
        }
        dismiss()
    }
}

/// Wrapper to make a filename Identifiable for sheet presentation.
struct SelectedFilename: Identifiable {
    let id = UUID()
    let value: String
    let attachmentID: UUID?
    init(_ value: String, attachmentID: UUID? = nil) {
        self.value = value
        self.attachmentID = attachmentID
    }
}

// MARK: - Proof thumbnail (3:4 dog-ear)

private struct ProofThumbnail: View {
    let attachment: Attachment

    var body: some View {
        Group {
            if let image = attachment.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    PT.inkRaised
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 18))
                        .foregroundStyle(PT.txt3)
                }
            }
        }
        .frame(width: 78, height: 104)
        .clipShape(DogEarShape(radius: 10, ear: 14))
        .overlay(DogEarShape(radius: 10, ear: 14).stroke(PT.hair, lineWidth: 1))
    }
}

#Preview {
    NavigationStack {
        Text("Preview requires SwiftData context")
    }
    .environmentObject(CloudImageSyncManager.shared)
}
