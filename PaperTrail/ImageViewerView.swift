import SwiftUI

/// Full-screen zoomable image viewer for attachment images.
struct ImageViewerView: View {
    let filename: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = ImageStorageManager.load(filename) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scale = value.magnification
                                }
                                .onEnded { _ in
                                    withAnimation(.spring(response: 0.3)) {
                                        scale = max(1.0, scale)
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                scale = scale > 1.0 ? 1.0 : 2.5
                            }
                        }
                } else {
                    ContentUnavailableView(
                        "Image not found",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("The file may have been moved or deleted.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
