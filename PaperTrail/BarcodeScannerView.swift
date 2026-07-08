import SwiftUI
import VisionKit

/// Live camera barcode scanner for the "Scan barcode" button next to the
/// serial number field (`EditRecordView`). Wraps VisionKit's
/// `DataScannerViewController` in barcode-only mode; the first recognized
/// barcode is reported via `onRecognize` and the caller dismisses the sheet.
///
/// Camera usage description is already configured at the project level (see
/// `INFOPLIST_KEY_NSCameraUsageDescription`).
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onRecognize: (String) -> Void

    /// Whether this device/OS combination can run the live scanner at all.
    /// Callers should hide the "Scan barcode" button entirely when this is
    /// `false` (simulators, and older/unsupported devices).
    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !context.coordinator.didStartScanning else { return }
        context.coordinator.didStartScanning = true
        do {
            try uiViewController.startScanning()
        } catch {
            AppLogger.error(
                "Barcode scanner failed to start: \(error.localizedDescription)",
                category: "extraction.barcode"
            )
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecognize: onRecognize)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onRecognize: (String) -> Void
        var didStartScanning = false
        private var didEmit = false

        init(onRecognize: @escaping (String) -> Void) {
            self.onRecognize = onRecognize
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didEmit else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item,
                   let payload = barcode.payloadStringValue,
                   !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    didEmit = true
                    onRecognize(payload)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            AppLogger.error(
                "Barcode scanner became unavailable: \(error)",
                category: "extraction.barcode"
            )
        }
    }
}

/// Sheet presenting `BarcodeScannerView` with a cancel affordance. The first
/// recognized barcode calls `onScan` and dismisses.
struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            BarcodeScannerView { payload in
                onScan(payload)
                dismiss()
            }
            .ignoresSafeArea()
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
