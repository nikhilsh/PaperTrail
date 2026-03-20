import SwiftUI
import SwiftData
import PhotosUI

struct CaptureView: View {
    @State private var showScanner = false
    @State private var showPhotoPicker = false
    @State private var scanType: AttachmentType = .receipt
    @State private var draftPayload: DraftPayload?
    @State private var isProcessing = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    private let scanningService = ScanningService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add proof of purchase")
                    .font(.title2.bold())

                Text("Capture now, search later.")
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Button {
                        scanType = .receipt
                        showScanner = true
                    } label: {
                        CaptureActionRow(
                            title: "Scan receipt",
                            subtitle: "Use the camera to scan a printed receipt.",
                            systemImage: "doc.viewfinder"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        scanType = .warranty
                        showScanner = true
                    } label: {
                        CaptureActionRow(
                            title: "Add warranty card",
                            subtitle: "Scan a warranty card or proof document.",
                            systemImage: "shield.lefthalf.filled"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        scanType = .other
                        showPhotoPicker = true
                    } label: {
                        CaptureActionRow(
                            title: "Import photo",
                            subtitle: "Pick an existing image from your library.",
                            systemImage: "photo.on.rectangle"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if isProcessing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Running OCR…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
                }

                Text("PaperTrail scans your document, extracts text with OCR, and lets you confirm key fields before saving.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Capture")
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

private struct DraftPayload: Identifiable, Hashable {
    let id = UUID()
    let type: AttachmentType
    let attachments: [Attachment]
    let ocr: OCRExtractionResult

    static func == (lhs: DraftPayload, rhs: DraftPayload) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct CaptureActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        CaptureView()
    }
    .environmentObject(CloudImageSyncManager.shared)
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
