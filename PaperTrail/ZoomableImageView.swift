import SwiftUI
import UIKit

/// Native pinch-zoom + pan for a full-screen image, the way Photos does it:
/// zoom anchors at the pinch point, the image pans while zoomed, edges
/// bounce, and double-tap toggles between fit and 3× at the tap point.
///
/// The previous SwiftUI `scaleEffect + MagnifyGesture` approach could only
/// scale around the center with no panning — a receipt's corners were
/// unreachable. `UIScrollView` has owned this interaction since iPhone OS 2;
/// wrapping it is the entire implementation.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scroll.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scroll.setZoomScale(1, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        /// Keep the image centered while it's smaller than the viewport in
        /// either axis (aspect-fit leaves letterbox space that UIScrollView
        /// would otherwise pin to the top-left).
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let dx = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
            let dy = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            imageView.center = CGPoint(
                x: scrollView.contentSize.width / 2 + dx,
                y: scrollView.contentSize.height / 2 + dy
            )
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let width = scroll.bounds.width / 3
                let height = scroll.bounds.height / 3
                scroll.zoom(
                    to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height),
                    animated: true
                )
            }
        }
    }
}

/// The bare close glyph both full-screen viewers share — no toolbar, no glass
/// circle backing; a shadow keeps it legible over bright receipt paper.
struct ViewerCloseButton: View {
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 4)
                .padding(14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}
