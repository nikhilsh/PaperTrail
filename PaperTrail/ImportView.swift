import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// "Bring it all in." (§4) — bulk backfill. Every imported image is routed
/// through the SAME on-device extraction pipeline (ScanningService →
/// OCR/Foundation Models + per-field confidence + CorrectionLogger) and lands in
/// the normal Review screen (DraftRecordView) for confirmation before saving.
/// Nothing is faked.
struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showEmailComingSoon = false
    @State private var isProcessing = false
    @State private var processingNote = ""
    @State private var reviewQueue: [DraftPayload] = []
    @State private var currentDraft: DraftPayload?
    @State private var copiedAddress = false

    private let scanningService = ScanningService()
    private let forwardingAddress = "receipts@in.papertrail.app"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(Text("Bring it\n").foregroundStyle(PT.txt))\(Text("all in.").foregroundStyle(PT.goldHi))")
                        .font(PTFont.serif(34, weight: 600))
                    Text("Most of your receipts already live somewhere. Pull them in — we read each one on-device and let you confirm before saving.")
                        .font(.system(size: 14))
                        .foregroundStyle(PT.txt2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                sourceRow(icon: "square.grid.2x2", title: "Photos",
                          sub: "Find receipts in your camera roll") { showPhotoPicker = true }
                sourceRow(icon: "shippingbox", title: "Files & PDFs",
                          sub: "Emailed invoices, scanned docs") { showFileImporter = true }
                sourceRow(icon: "envelope", title: "Email receipts",
                          sub: "Connect Gmail or Apple Mail") { showEmailComingSoon = true }

                forwardingCard
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.bottom, 130)
        }
        .ptScreen()
        .navigationBarBackButtonHidden()
        .overlay { if isProcessing { processingOverlay } }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Settings")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: 20, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await processPhotoItems(items) }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.pdf, .image],
                      allowsMultipleSelection: true) { result in
            if case let .success(urls) = result {
                Task { await processFiles(urls) }
            }
        }
        .alert("Coming soon", isPresented: $showEmailComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Connecting Gmail or Apple Mail is on the way. For now, forward receipts to your private address, or import from Photos and Files.")
        }
        .navigationDestination(item: $currentDraft) { payload in
            DraftRecordView(seedType: payload.type, seededAttachments: payload.attachments, seededOCR: payload.ocr)
        }
        .onChange(of: currentDraft) { _, newValue in
            // When the review screen pops (item cleared), advance to the next import.
            if newValue == nil { advanceQueueSoon() }
        }
    }

    // MARK: Source rows

    private func sourceRow(icon: String, title: String, sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(PT.gold)
                    .frame(width: 40, height: 40)
                    .background(Color(hex: 0xE7DCC4, alpha: 0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(PT.hair2, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(PTFont.serif(18, weight: 600)).foregroundStyle(PT.txt)
                    Text(sub).font(.system(size: 12.5)).foregroundStyle(PT.txt3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(PT.txt3)
            }
            .padding(16)
            .background(PT.inkCardDark, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PT.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var forwardingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FORWARD ANYTIME")
                .ptMonoLabel(9.5, tracking: 2.4)
                .foregroundStyle(PT.onPaper3)
            Text("Forward any order confirmation to your private inbox and it files itself:")
                .font(.system(size: 12.5))
                .foregroundStyle(PT.onPaper2)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(forwardingAddress)
                    .font(PTFont.mono(13, medium: true))
                    .foregroundStyle(PT.onPaper)
                Spacer()
                Button {
                    UIPasteboard.general.string = forwardingAddress
                    copiedAddress = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedAddress = false }
                } label: {
                    Image(systemName: copiedAddress ? "checkmark" : "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(PT.goldDeep)
                }
            }
            .padding(12)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(PT.onPaperHair)
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: false)
        .padding(.top, 6)
    }

    private var processingOverlay: some View {
        ZStack {
            PT.inkCanvas.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().controlSize(.large).tint(PT.gold)
                Text("Reading your receipts…")
                    .font(PTFont.serif(20, weight: 500))
                    .foregroundStyle(PT.txt)
                if !processingNote.isEmpty {
                    Text(processingNote)
                        .ptMonoLabel(9, tracking: 1.4)
                        .foregroundStyle(PT.txt3)
                }
            }
        }
    }

    // MARK: Processing — routes through the real extraction pipeline

    private func processPhotoItems(_ items: [PhotosPickerItem]) async {
        isProcessing = true
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photoItems = []
        await processImages(images)
    }

    private func processFiles(_ urls: [URL]) async {
        isProcessing = true
        var images: [UIImage] = []
        for url in urls {
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            images.append(contentsOf: ImportPipeline.images(fromFileURL: url))
        }
        await processImages(images)
    }

    private func processImages(_ images: [UIImage]) async {
        guard !images.isEmpty else { isProcessing = false; return }
        let learned = MerchantLearningService(modelContext: modelContext).learnedMerchantNames()
        var payloads: [DraftPayload] = []
        for (index, image) in images.enumerated() {
            processingNote = "Reading \(index + 1) of \(images.count)"
            let result = await scanningService.process(images: [image], type: .receipt, learnedMerchants: learned)
            payloads.append(DraftPayload(type: .receipt, attachments: result.attachments, ocr: result.ocr))
        }
        isProcessing = false
        processingNote = ""
        reviewQueue = payloads
        advanceQueue()
    }

    private func advanceQueue() {
        guard currentDraft == nil, !reviewQueue.isEmpty else { return }
        currentDraft = reviewQueue.removeFirst()
    }

    private func advanceQueueSoon() {
        guard !reviewQueue.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { advanceQueue() }
    }
}
