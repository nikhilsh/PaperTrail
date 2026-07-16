import Foundation

/// Local-only on-disk storage for PDF manuals attached via `manualOnFile`
/// (docs/design-v3/V3_BRIEF.md §5).
///
/// **Deliberately NOT modeled as an `Attachment`.** `Attachment.image`
/// decodes bytes via `UIImage(data:)` (`ImageStorageManager.load`), which
/// returns `nil` for PDF data, and `RecordDetailView.documentAttachments`
/// pulls every non-product-photo attachment into the "Proof on file"
/// horizontal strip regardless of `type` — a manual routed through
/// `Attachment` would show up there as a permanently-broken thumbnail (the
/// `.task` download-retry loop keyed on `attachment.image == nil` would
/// also never settle). `CloudImageSyncManager.upload`/`download` are
/// themselves byte-agnostic (they just copy whatever `CKAsset` file URL
/// they're given), so cloud sync of the raw PDF bytes wouldn't literally
/// crash — but the whole "ImageAsset" pipeline is built around the
/// image-thumbnail contract above, so wiring a manual through it still
/// trips the same broken-thumbnail problem. Given that, this wave stores
/// manuals in a small local-only store instead, matching `ImageStorageManager`'s
/// shape (flat directory, filename-keyed). **Follow-up:** sync manuals
/// across devices — either a dedicated CKAsset record type (mirroring
/// `ImageAsset` but without touching `Attachment`/the Proof strip), or a
/// third field on `PurchaseRecord` once the shape is settled.
///
/// One manual per record: `<recordID>.pdf` in `Application Support/Manuals/`,
/// with a small JSON sidecar index for display metadata (there's no
/// SwiftData model backing this store, so metadata has nowhere else to
/// live).
nonisolated struct ManualRecord: Codable, Equatable, Sendable {
    var filename: String
    var displayName: String
    var byteCount: Int
    var addedAt: Date
}

enum ManualStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Manuals", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for recordID: UUID) -> URL {
        directory.appendingPathComponent("\(recordID.uuidString).pdf")
    }

    private static var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }

    /// Copies `sourceURL` (already access-scoped by the caller — e.g. from
    /// inside a `fileImporter` completion) into local storage as the manual
    /// for `recordID`. Overwrites any existing manual for the record.
    /// Returns `nil` (and logs to Sentry via `AppLogger`) on any filesystem
    /// failure rather than throwing, matching `ImageStorageManager.save`'s
    /// shape.
    @discardableResult
    static func save(sourceURL: URL, displayName: String, for recordID: UUID) -> ManualRecord? {
        let dest = fileURL(for: recordID)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch {
            AppLogger.error("ManualStore: failed to copy \(sourceURL.lastPathComponent) for record \(recordID): \(error)", category: "manual")
            return nil
        }
        let byteCount = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
        let record = ManualRecord(filename: dest.lastPathComponent, displayName: displayName, byteCount: byteCount ?? 0, addedAt: .now)
        setIndexEntry(record, for: recordID)
        AppLogger.info("ManualStore: saved manual for record \(recordID) (\(byteCount ?? 0) bytes)", category: "manual")
        return record
    }

    /// Metadata for `recordID`'s manual, if one is on file.
    static func manual(for recordID: UUID) -> ManualRecord? {
        indexEntry(for: recordID)
    }

    /// The manual's on-disk URL for QuickLook, or `nil` if none is on file
    /// or the file has gone missing out from under the index (defensive —
    /// never crash the Papers tab over a dangling entry).
    static func url(for recordID: UUID) -> URL? {
        guard indexEntry(for: recordID) != nil else { return nil }
        let dest = fileURL(for: recordID)
        return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
    }

    /// Removes the manual (file + index entry) for `recordID`. No-op if
    /// there isn't one. Called from `RecordDetailView.deleteRecord()`
    /// alongside the existing `Attachment`/image cleanup so deleting a
    /// record doesn't leave an orphaned PDF behind.
    static func delete(for recordID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: recordID))
        removeIndexEntry(for: recordID)
    }

    // MARK: - Index (recordID -> ManualRecord), small JSON sidecar file.
    //
    // Not SwiftData-backed (this store is intentionally outside the
    // CloudKit-synced schema per the type doc above), so metadata lives in
    // its own tiny JSON file next to the PDFs — same directory, same
    // read-modify-write-whole-file approach `ImageStorageManager` avoids
    // needing only because it has no metadata to persist.

    private static func loadIndex() -> [String: ManualRecord] {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([String: ManualRecord].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveIndex(_ index: [String: ManualRecord]) {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static func indexEntry(for recordID: UUID) -> ManualRecord? {
        loadIndex()[recordID.uuidString]
    }

    private static func setIndexEntry(_ record: ManualRecord, for recordID: UUID) {
        var index = loadIndex()
        index[recordID.uuidString] = record
        saveIndex(index)
    }

    private static func removeIndexEntry(for recordID: UUID) {
        var index = loadIndex()
        index.removeValue(forKey: recordID.uuidString)
        saveIndex(index)
    }
}

extension ManualRecord {
    /// "4.2 MB" / "312 KB" — `ByteCountFormatter` file style, matching the
    /// C2 mock's "QA55S90D user guide · PDF · 4.2 MB" subtitle.
    nonisolated var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}
