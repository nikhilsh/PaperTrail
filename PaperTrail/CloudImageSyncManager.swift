import Foundation
import CloudKit
import UIKit
import Combine

/// Manages syncing attachment images across devices using CKAsset in a dedicated
/// CloudKit record type ("ImageAsset"). This runs alongside (not inside) the
/// SwiftData/CloudKit mirror — the SwiftData store syncs lightweight Attachment
/// metadata, while this manager handles the heavy binary blobs separately.
///
/// Record type layout in CloudKit:
///   ImageAsset {
///     attachmentID: String      // matches Attachment.id.uuidString
///     asset: CKAsset            // the JPEG image data
///     recordID: CKRecord.ID     // auto, uses "img-<attachmentID>" as record name
///   }
@MainActor
final class CloudImageSyncManager: ObservableObject {

    static let shared = CloudImageSyncManager()

    // MARK: - Constants

    private let containerID = "iCloud.nikhilsh.PaperTrail"
    private let recordType = "ImageAsset"
    private let jpegQuality: CGFloat = 0.80

    // MARK: - State

    /// Tracks which attachment IDs are currently being uploaded/downloaded.
    @Published private(set) var activeTransfers: Set<UUID> = []

    /// Errors keyed by attachment ID for UI display.
    @Published private(set) var transferErrors: [UUID: String] = [:]

    // MARK: - Private

    private lazy var container: CKContainer = {
        CKContainer(identifier: containerID)
    }()

    private var privateDB: CKDatabase {
        container.privateCloudDatabase
    }

    private init() {}

    // MARK: - Upload

    /// Upload an image for the given attachment to CloudKit as a CKAsset.
    /// Call this after the attachment has been saved locally.
    ///
    /// - Parameters:
    ///   - attachmentID: The UUID of the Attachment model object.
    ///   - localFilename: The on-disk filename in the Attachments directory.
    /// - Returns: The CKRecord.ID.recordName of the created/updated record, or nil on failure.
    @discardableResult
    func upload(attachmentID: UUID, localFilename: String) async -> String? {
        guard !activeTransfers.contains(attachmentID) else {
            AppLogger.info("Upload already in progress for \(attachmentID)", category: "cloud.image")
            return nil
        }

        activeTransfers.insert(attachmentID)
        transferErrors.removeValue(forKey: attachmentID)
        defer { activeTransfers.remove(attachmentID) }

        let fileURL = ImageStorageManager.url(for: localFilename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let msg = "Local image file not found: \(localFilename)"
            AppLogger.error(msg, category: "cloud.image")
            transferErrors[attachmentID] = msg
            return nil
        }

        let recordName = Self.recordName(for: attachmentID)
        let recordID = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["attachmentID"] = attachmentID.uuidString as CKRecordValue
        record["asset"] = CKAsset(fileURL: fileURL)

        do {
            let saved = try await privateDB.save(record)
            AppLogger.info("Uploaded image for attachment \(attachmentID)", category: "cloud.image")
            return saved.recordID.recordName
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Record already exists — update it
            do {
                let existing = try await privateDB.record(for: recordID)
                existing["asset"] = CKAsset(fileURL: fileURL)
                let saved = try await privateDB.save(existing)
                AppLogger.info("Updated existing image for attachment \(attachmentID)", category: "cloud.image")
                return saved.recordID.recordName
            } catch {
                let msg = "Failed to resolve conflict for \(attachmentID): \(error.localizedDescription)"
                AppLogger.error(msg, category: "cloud.image")
                transferErrors[attachmentID] = msg
                return nil
            }
        } catch {
            let msg = "Upload failed for \(attachmentID): \(error.localizedDescription)"
            AppLogger.error(msg, category: "cloud.image")
            transferErrors[attachmentID] = msg
            return nil
        }
    }

    // MARK: - Download

    /// Download an image for the given attachment from CloudKit.
    /// Saves it to the local Attachments directory with the given filename.
    ///
    /// - Parameters:
    ///   - attachmentID: The UUID of the Attachment model object.
    ///   - localFilename: The filename to save to locally.
    /// - Returns: `true` if the image was successfully downloaded and saved.
    @discardableResult
    func download(attachmentID: UUID, localFilename: String) async -> Bool {
        guard !activeTransfers.contains(attachmentID) else {
            AppLogger.info("Download already in progress for \(attachmentID)", category: "cloud.image")
            return false
        }

        // If the file already exists locally, skip download
        let fileURL = ImageStorageManager.url(for: localFilename)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            AppLogger.info("Image already exists locally for \(attachmentID), skipping download", category: "cloud.image")
            return true
        }

        activeTransfers.insert(attachmentID)
        transferErrors.removeValue(forKey: attachmentID)
        defer { activeTransfers.remove(attachmentID) }

        let recordName = Self.recordName(for: attachmentID)
        let recordID = CKRecord.ID(recordName: recordName)

        do {
            let record = try await privateDB.record(for: recordID)
            guard let asset = record["asset"] as? CKAsset,
                  let assetURL = asset.fileURL else {
                let msg = "No asset data in CloudKit record for \(attachmentID)"
                AppLogger.error(msg, category: "cloud.image")
                transferErrors[attachmentID] = msg
                return false
            }

            // Copy from CloudKit temp location to our Attachments directory
            let data = try Data(contentsOf: assetURL)
            try data.write(to: fileURL, options: .atomic)

            AppLogger.info("Downloaded image for attachment \(attachmentID)", category: "cloud.image")
            return true
        } catch let error as CKError where error.code == .unknownItem {
            // Record not yet uploaded by the source device — not an error, just not ready
            AppLogger.info("Image not yet available in CloudKit for \(attachmentID)", category: "cloud.image")
            transferErrors[attachmentID] = "Image not yet synced from source device"
            return false
        } catch {
            let msg = "Download failed for \(attachmentID): \(error.localizedDescription)"
            AppLogger.error(msg, category: "cloud.image")
            transferErrors[attachmentID] = msg
            return false
        }
    }

    // MARK: - Delete

    /// Remove the CloudKit image record for an attachment.
    func delete(attachmentID: UUID) async {
        let recordName = Self.recordName(for: attachmentID)
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            try await privateDB.deleteRecord(withID: recordID)
            AppLogger.info("Deleted cloud image for attachment \(attachmentID)", category: "cloud.image")
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone, that's fine
        } catch {
            AppLogger.error("Failed to delete cloud image for \(attachmentID): \(error.localizedDescription)", category: "cloud.image")
        }
    }

    // MARK: - Batch Sync

    /// Attempt to download images for all attachments that lack a local file.
    /// This is the "pull missing images on launch" path.
    func syncMissingImages(attachments: [AttachmentSyncInfo]) async {
        let missing = attachments.filter { info in
            !FileManager.default.fileExists(atPath: ImageStorageManager.url(for: info.localFilename).path)
        }

        guard !missing.isEmpty else { return }
        AppLogger.info("Syncing \(missing.count) missing images from CloudKit", category: "cloud.image")

        await withTaskGroup(of: Void.self) { group in
            for info in missing {
                group.addTask { @MainActor in
                    await self.download(attachmentID: info.id, localFilename: info.localFilename)
                }
            }
        }
    }

    /// Upload all images that exist locally but haven't been pushed yet.
    /// Checks CloudKit for existence before uploading to avoid duplicates.
    func uploadMissingImages(attachments: [AttachmentSyncInfo]) async {
        guard !attachments.isEmpty else { return }
        AppLogger.info("Checking \(attachments.count) attachments for missing cloud images", category: "cloud.image")

        await withTaskGroup(of: Void.self) { group in
            for info in attachments {
                let fileURL = ImageStorageManager.url(for: info.localFilename)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

                group.addTask { @MainActor in
                    // Check if already in CloudKit
                    let recordName = Self.recordName(for: info.id)
                    let recordID = CKRecord.ID(recordName: recordName)
                    do {
                        _ = try await self.privateDB.record(for: recordID)
                        // Already exists, skip
                    } catch {
                        // Not found or error — try uploading
                        await self.upload(attachmentID: info.id, localFilename: info.localFilename)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// Deterministic record name for an attachment's image asset.
    static func recordName(for attachmentID: UUID) -> String {
        "img-\(attachmentID.uuidString)"
    }
}

/// Lightweight struct for passing attachment info to sync operations
/// without requiring SwiftData model context access.
struct AttachmentSyncInfo: Sendable {
    let id: UUID
    let localFilename: String
}
