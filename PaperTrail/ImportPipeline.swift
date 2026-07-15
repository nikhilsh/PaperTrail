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

    static func imagesFromPDF(_ url: URL) -> [UIImage] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var result: [UIImage] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
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
        return result
    }
}

/// Temp holding area for files handed to PaperTrail via "Open in…" (Mail,
/// Files, another app's share sheet). `onOpenURL` receives a security-scoped
/// URL that's only guaranteed valid for the duration of that callback, so the
/// file is copied here before the scope is released and before async
/// extraction (OCR/FM, which can take a few seconds) runs.
enum DocumentInbox {
    private static var directory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
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
            AppLogger.error("DocumentInbox copy failed for \(url.lastPathComponent): \(error)", category: "import")
            return nil
        }
    }
}
