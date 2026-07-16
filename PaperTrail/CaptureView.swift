import SwiftUI
import SwiftData
import PhotosUI

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var scanType: AttachmentType = .receipt
    @State private var draftPayload: DraftPayload?
    @State private var isProcessing = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    private let scanningService = ScanningService()

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("New record")
                    .font(PTFont.serif(30, weight: 600))
                    .foregroundStyle(PT.txt)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                cameraFrame

                Text("Drop a receipt in the frame — we read the rest.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(PT.txt2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    Button {
                        scanType = .receipt
                        showScanner = true
                    } label: {
                        Label("Capture receipt", systemImage: "camera.fill")
                    }
                    .buttonStyle(PTGoldButtonStyle())

                    Button {
                        scanType = .other
                        showPhotoPicker = true
                    } label: {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(PTOutlineButtonStyle())
                }
                .padding(.horizontal, 4)

                Text("PaperTrail reads your receipt on-device, pulls out the\nkey fields, and lets you confirm them before saving.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(PT.txt3)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
        .ptScreen()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PT.txt2)
                }
            }
        }
        .overlay {
            if isProcessing { scanningOverlay }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView(
                onScanComplete: { images in
                    showScanner = false
                    Task { await processScan(images: images, type: scanType) }
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await processPhotoPick(item: newItem) }
            selectedPhotoItem = nil
        }
        .navigationDestination(item: $draftPayload) { payload in
            DraftRecordView(
                seedType: payload.type,
                seededAttachments: payload.attachments,
                seededOCR: payload.ocr
            )
        }
    }

    // MARK: Ready — dark camera frame with gold corner brackets

    private var cameraFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: 0x06060A))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PT.hair, lineWidth: 1))
            VStack(spacing: 12) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 46, weight: .ultraLight))
                    .foregroundStyle(PT.txt3)
                Text("Receipt in frame")
                    .ptMonoLabel(9, tracking: 1.6)
                    .foregroundStyle(PT.txt3)
            }
            CornerBrackets(color: PT.gold, length: 26, thickness: 2, inset: 12)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
    }

    // MARK: Scanning overlay

    private var scanningOverlay: some View {
        ZStack {
            PT.inkCanvas.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(PT.gold)
                Text("Reading your receipt…")
                    .font(PTFont.serif(20, weight: 500))
                    .foregroundStyle(PT.txt)
                Text("On-device OCR + Apple Intelligence")
                    .ptMonoLabel(9, tracking: 1.6)
                    .foregroundStyle(PT.txt3)
            }
        }
    }

    private func processScan(images: [UIImage], type: AttachmentType) async {
        isProcessing = true
        let learned = MerchantLearningService(modelContext: modelContext).learnedMerchantNames()
        let result = await scanningService.process(images: images, type: type, learnedMerchants: learned)
        isProcessing = false
        draftPayload = DraftPayload(type: type, attachments: result.attachments, ocr: result.ocr)
    }

    private func processPhotoPick(item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        let learned = MerchantLearningService(modelContext: modelContext).learnedMerchantNames()
        let result = await scanningService.process(images: [image], type: scanType, learnedMerchants: learned)
        draftPayload = DraftPayload(type: scanType, attachments: result.attachments, ocr: result.ocr)
    }
}

// MARK: - Supporting types

struct DraftPayload: Identifiable, Hashable {
    let id = UUID()
    let type: AttachmentType
    let attachments: [Attachment]
    let ocr: OCRExtractionResult
    /// True when `attachments` is a single product photo (the add-sheet's
    /// "Photograph the thing", v3 §3) rather than proof of purchase — tells
    /// `DraftRecordView.saveRecord()` to file it as `productImageAttachmentID`
    /// instead of a regular document attachment. Defaults false so every
    /// existing call site (scan, Photos import, Mail/Files import) is unaffected.
    var seedsProductImage: Bool = false

    static func == (lhs: DraftPayload, rhs: DraftPayload) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#Preview {
    NavigationStack {
        CaptureView()
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
    .environmentObject(CloudImageSyncManager.shared)
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
