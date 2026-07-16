import SwiftUI
import UIKit

/// UIActivityViewController wrapper for SwiftUI.
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    /// Fires once the share sheet's own completion handler runs — i.e. the
    /// user actually picked an activity (or explicitly cancelled), not just
    /// "the sheet was presented". `completed`/`activityType` are available
    /// but unused here: callers that care about the handover actually
    /// happening (`PassItOnBuilderView`) want "the user finished with the
    /// sheet, whatever they did", not "they specifically shared".
    var onComplete: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
