import SwiftUI

/// Full-screen zoomable image viewer for attachment images. Also hosts the
/// on-device "Translate this receipt" affordance (`Flag.translate`) when the
/// attachment carries OCR text — this is the one place in
/// `RecordDetailView`'s subview tree where a specific document's OCR text is
/// addressable by attachment id, so the panel lives here.
struct ImageViewerView: View {
    let filename: String
    var attachmentID: UUID?
    /// The attachment's raw OCR text, if any — passed down from
    /// `RecordDetailView.openAttachment` via `SelectedFilename.ocrText`.
    /// Only used to drive language detection + on-device translation; never
    /// persisted here.
    var ocrText: String?
    @Environment(\.dismiss) private var dismiss
    @State private var loadedImage: UIImage?
    @State private var isDownloading = false

    private var trimmedOCRText: String? {
        guard let ocrText, !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return ocrText
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                if let image = loadedImage ?? ImageStorageManager.load(filename) {
                    ZoomableImageView(image: image)
                        .ignoresSafeArea()
                } else if isDownloading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Downloading from iCloud…")
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.subheadline)
                    }
                } else {
                    ContentUnavailableView(
                        "Image not found",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("The file may have been moved or deleted.")
                    )
                }

                if FeatureFlags.isOn(.translate), let attachmentID, let trimmedOCRText {
                    ReceiptTranslationPanel(attachmentID: attachmentID, ocrText: trimmedOCRText)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
            }
            .task {
                // If no local image and we have an attachment ID, try downloading
                if ImageStorageManager.load(filename) == nil, let attachmentID {
                    isDownloading = true
                    let success = await CloudImageSyncManager.shared.download(
                        attachmentID: attachmentID,
                        localFilename: filename
                    )
                    isDownloading = false
                    if success {
                        loadedImage = ImageStorageManager.load(filename)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                ViewerCloseButton { dismiss() }
                    .padding(.top, 4)
                    .padding(.trailing, 6)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
