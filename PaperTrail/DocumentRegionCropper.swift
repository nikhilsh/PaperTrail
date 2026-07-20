import Foundation
import UIKit
import Vision

/// Crops an image down to the detected document page before OCR.
///
/// Screenshots and photos of screens carry UI chrome — a status-bar clock, a
/// back-to-app breadcrumb — that OCR reads far more reliably than the shrunken
/// document body, so the chrome ends up winning the field heuristics. Cropping
/// to the detected page removes the chrome and boosts the effective resolution
/// of the document text in one step.
///
/// Camera scans are already perspective-cropped by the document scanner, so
/// their detected region covers nearly the whole frame and no crop happens
/// (see `maximumAreaFraction`).
enum DocumentRegionCropper {

    /// Minimum Vision confidence before trusting a detected document region.
    static let minimumConfidence: Float = 0.5

    /// Crop only when the detected page fills less than this fraction of the
    /// frame — a near-full-frame detection (typical for camera scans) gains
    /// nothing from re-cropping and risks shaving off edge text.
    static let maximumAreaFraction: CGFloat = 0.85

    /// Margin added around the detected region, as a fraction of each side,
    /// so a slightly-tight detection doesn't clip the first/last text line.
    static let marginFraction: CGFloat = 0.04

    /// Returns the image cropped to the detected document region, or nil when
    /// no crop should be applied (no document found, low confidence, or the
    /// document already fills the frame).
    static func croppedToDocument(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            AppLogger.warn(
                "Document segmentation failed: \(error.localizedDescription)",
                category: "extraction.crop"
            )
            return nil
        }

        guard let observation = request.results?.first,
              observation.confidence >= minimumConfidence else { return nil }

        guard let rect = cropRect(
            boundingBox: observation.boundingBox,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height
        ) else { return nil }

        guard let cropped = cgImage.cropping(to: rect) else { return nil }

        let areaPercent = Int((observation.boundingBox.width * observation.boundingBox.height) * 100)
        AppLogger.info(
            "Cropped to detected document region (\(areaPercent)% of frame, confidence \(String(format: "%.2f", observation.confidence)))",
            category: "extraction.crop"
        )
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Converts a Vision normalized bounding box (lower-left origin) into a
    /// pixel-space crop rect with margin, or nil when the region already
    /// covers most of the frame. Pure — unit-tested directly.
    static func cropRect(boundingBox: CGRect, pixelWidth: Int, pixelHeight: Int) -> CGRect? {
        guard boundingBox.width > 0, boundingBox.height > 0 else { return nil }
        guard boundingBox.width * boundingBox.height < maximumAreaFraction else { return nil }

        let expanded = boundingBox.insetBy(
            dx: -boundingBox.width * marginFraction,
            dy: -boundingBox.height * marginFraction
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !expanded.isEmpty else { return nil }

        let width = CGFloat(pixelWidth)
        let height = CGFloat(pixelHeight)
        // Vision's normalized coordinates have a lower-left origin; CGImage
        // cropping uses an upper-left origin, so the y axis flips.
        return CGRect(
            x: expanded.minX * width,
            y: (1 - expanded.maxY) * height,
            width: expanded.width * width,
            height: expanded.height * height
        )
    }
}
