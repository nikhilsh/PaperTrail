import SwiftUI
import SwiftData
import PhotosUI

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
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
                framingCard

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
            ToolbarItem(placement: .topBarLeading) {
                Text("New record").ptWordmark()
            }
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

    // MARK: Ready — framing card

    private var framingCard: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(PT.onPaper3.opacity(0.5))
                Image(systemName: "viewfinder")
                    .font(.system(size: 54, weight: .ultraLight))
                    .foregroundStyle(PT.goldDeep)
            }
            .frame(height: 200)

            VStack(spacing: 4) {
                Text("Frame your receipt")
                    .font(PTFont.serif(20, weight: 600))
                    .foregroundStyle(PT.onPaper)
                Text("Lay it flat, good light, edges in view.")
                    .font(PTFont.mono(10.5))
                    .foregroundStyle(PT.onPaper3)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .paperCard(goldFold: true)
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
        let result = await scanningService.process(images: images, type: type)
        isProcessing = false
        draftPayload = DraftPayload(type: type, attachments: result.attachments, ocr: result.ocr)
    }

    private func processPhotoPick(item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        let result = await scanningService.process(images: [image], type: scanType)
        draftPayload = DraftPayload(type: scanType, attachments: result.attachments, ocr: result.ocr)
    }
}

// MARK: - Supporting types

struct DraftPayload: Identifiable, Hashable {
    let id = UUID()
    let type: AttachmentType
    let attachments: [Attachment]
    let ocr: OCRExtractionResult

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
