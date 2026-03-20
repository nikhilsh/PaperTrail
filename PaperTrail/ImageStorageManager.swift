import Foundation
import UIKit

/// Manages on-disk image storage in the app's documents directory.
/// Images are currently local-only; SwiftData/CloudKit syncs attachment metadata, not binary image blobs.
struct ImageStorageManager {
    private static var imagesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Save an image to disk with an auto-generated filename. Returns the filename.
    @discardableResult
    static func save(_ image: UIImage, quality: CGFloat = 0.85) -> String? {
        let filename = UUID().uuidString + ".jpg"
        return save(image, withFilename: filename, quality: quality) ? filename : nil
    }

    /// Save an image to disk with a specific filename. Returns success.
    @discardableResult
    static func save(_ image: UIImage, withFilename filename: String, quality: CGFloat = 0.85) -> Bool {
        guard let data = image.jpegData(compressionQuality: quality) else { return false }
        let url = imagesDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            print("ImageStorageManager: failed to write \(filename): \(error)")
            return false
        }
    }

    /// Load an image from disk by filename.
    static func load(_ filename: String) -> UIImage? {
        let url = imagesDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Delete an image from disk.
    static func delete(_ filename: String) {
        let url = imagesDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// Full file URL for a filename.
    static func url(for filename: String) -> URL {
        imagesDirectory.appendingPathComponent(filename)
    }

    /// Get JPEG data for an image at the given quality.
    static func jpegData(for image: UIImage, quality: CGFloat = 0.85) -> Data? {
        image.jpegData(compressionQuality: quality)
    }
}
