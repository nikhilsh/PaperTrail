import Foundation
import UIKit
import Vision

/// Sweeps a scanned page image for barcodes typical of device serial numbers
/// (asset tags, warranty cards, product boxes), off the main actor, using
/// Vision's `DetectBarcodesRequest`. Runs alongside OCR text extraction —
/// see `ScanningService.process(images:type:learnedMerchants:)`.
///
/// Never throws: a detection failure degrades to "no barcodes found" (mirrors
/// how OCR/Foundation Model extraction degrade gracefully per the extraction
/// architecture), with the failure logged and sent to Sentry so it's
/// diagnosable without a device.
struct BarcodeDetectionService: Sendable {

    /// Symbologies commonly used to encode a device serial or product/model
    /// code on receipts, warranty cards, and product packaging.
    private static let symbologies: [BarcodeSymbology] = [
        .code128, .code39, .dataMatrix, .qr, .ean13,
    ]

    /// Decoded barcode payload strings found on the page, in the order
    /// Vision returns them. Callers run `SerialCandidateFilter` over the
    /// result to decide which (if any) look like a serial number.
    func detectPayloads(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        do {
            var request = DetectBarcodesRequest()
            request.symbologies = Self.symbologies
            let observations = try await request.perform(on: cgImage)
            let payloads = observations.compactMap(\.payloadString)
            AppLogger.info(
                "Barcode sweep found \(observations.count) barcode(s), \(payloads.count) with a payload",
                category: "extraction.barcode"
            )
            return payloads
        } catch {
            AppLogger.error(
                "Barcode detection failed: \(error.localizedDescription)",
                category: "extraction.barcode"
            )
            return []
        }
    }
}
