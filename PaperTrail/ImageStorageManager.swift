import Foundation
import UIKit

/// Manages on-disk image storage in the app's documents directory.
struct ImageStorageManager {
    private static var imagesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Save an image to disk and return the filename.
    @discardableResult
    static func save(_ image: UIImage, quality: CGFloat = 0.85) -> String? {
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        let filename = UUID().uuidString + ".jpg"
        let url = imagesDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            print("ImageStorageManager: failed to write \(filename): \(error)")
            return nil
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
}
