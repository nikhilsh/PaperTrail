import UIKit
import PDFKit

/// Shared "file URL(s) → images" extraction used by both the in-app Import
/// flow (`ImportView`, Photos/Files picker) and Mail/Files "Open in
/// PaperTrail" (`AppShellView.onOpenURL`'s file-URL branch, via
/// `DocumentInbox`). Kept in one place so PDF rasterization isn't duplicated
/// between the two entry points.
enum ImportPipeline {

    /// Renders images from one or more local file URLs — PDF pages are
    /// rasterized, everything else is decoded as a single image. Callers
    /// handling externally security-scoped URLs (e.g. `.fileImporter`) are
    /// responsible for `startAccessingSecurityScopedResource` around each URL.
    static func images(fromFileURLs urls: [URL]) -> [UIImage] {
        urls.flatMap { images(fromFileURL: $0) }
    }

    static func images(fromFileURL url: URL) -> [UIImage] {
        if url.pathExtension.lowercased() == "pdf" {
            return imagesFromPDF(url)
        } else if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            return [image]
        }
        return []
    }

    /// A page-count cap protects against jetsam on huge scanned PDFs — nobody
    /// needs more than the first 20 pages rasterized into a single receipt import.
    static let maxPDFPages = 20
    /// Longest output edge, in pixels, any rasterized page is allowed to reach.
    static let maxRasterEdge: CGFloat = 4096
    /// Pages whose PDF-point mediaBox exceeds this in either dimension are
    /// almost certainly malformed/degenerate and are skipped rather than risk
    /// an enormous allocation.
    static let maxPageDimension: CGFloat = 20_000

    static func imagesFromPDF(_ url: URL) -> [UIImage] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var result: [UIImage] = []
        let pageCount = doc.pageCount
        let cappedCount = min(pageCount, maxPDFPages)
        if pageCount > maxPDFPages {
            AppLogger.warn("PDF has \(pageCount) pages, truncating to \(maxPDFPages)", category: "import")
        }
        for i in 0..<cappedCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width <= maxPageDimension, bounds.height <= maxPageDimension else {
                AppLogger.warn("Skipping oversized PDF page \(i): \(Int(bounds.width))x\(Int(bounds.height))pt", category: "import")
                continue
            }
            autoreleasepool {
                let longestEdge = max(bounds.width, bounds.height)
                let scale: CGFloat = longestEdge > 0 ? min(2, maxRasterEdge / longestEdge) : 2
                let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                let renderer = UIGraphicsImageRenderer(size: size)
                let image = renderer.image { ctx in
                    UIColor.white.set()
                    ctx.fill(CGRect(origin: .zero, size: size))
                    ctx.cgContext.translateBy(x: 0, y: size.height)
                    ctx.cgContext.scaleBy(x: scale, y: -scale)
                    page.draw(with: .mediaBox, to: ctx.cgContext)
                }
                result.append(image)
            }
        }
        return result
    }
}

/// Temp holding area for files handed to PaperTrail via "Open in…" (Mail,
/// Files, another app's share sheet). `onOpenURL` receives a security-scoped
/// URL that's only guaranteed valid for the duration of that callback, so the
/// file is copied here before the scope is released and before async
/// extraction (OCR/FM, which can take a few seconds) runs.
enum DocumentInbox {
    private static var baseURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
    }

    private static var directory: URL {
        let dir = baseURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies `url` into the inbox under a fresh UUID-prefixed filename
    /// (preserving its extension) and returns the local copy's URL, or `nil`
    /// if the copy failed.
    static func copy(_ url: URL) -> URL? {
        let ext = url.pathExtension
        let filename = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
        let destination = directory.appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            AppLogger.error("DocumentInbox copy failed: \(error)", category: "import")
            return nil
        }
    }

    /// Removes a single inbox copy once it's no longer needed (extraction
    /// has consumed it, success or failure).
    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Purges the entire inbox directory — called once at app launch so
    /// copies left behind by a killed/crashed import don't accumulate forever.
    static func purgeAll() {
        try? FileManager.default.removeItem(at: baseURL)
    }
}
