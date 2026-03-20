import SwiftUI

/// Small overlay indicator for attachment thumbnails showing cloud sync status.
struct CloudImageStatusOverlay: View {
    let attachmentID: UUID
    let hasLocalImage: Bool
    @ObservedObject var syncManager: CloudImageSyncManager

    private var isTransferring: Bool {
        syncManager.activeTransfers.contains(attachmentID)
    }

    private var hasError: Bool {
        syncManager.transferErrors[attachmentID] != nil
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isTransferring {
                syncBadge(icon: "arrow.triangle.2.circlepath", color: .blue, spinning: true)
            } else if !hasLocalImage {
                syncBadge(icon: "icloud.and.arrow.down", color: .orange, spinning: false)
            } else if hasError {
                syncBadge(icon: "exclamationmark.icloud", color: .red, spinning: false)
            }
            // When local image exists and no error/transfer, show nothing (fully synced)
        }
    }

    @ViewBuilder
    private func syncBadge(icon: String, color: Color, spinning: Bool) -> some View {
        Image(systemName: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(3)
            .background(color, in: Circle())
            .shadow(radius: 1)
            .padding(2)
    }
}
