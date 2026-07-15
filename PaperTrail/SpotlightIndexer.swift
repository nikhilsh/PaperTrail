import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import SwiftData

/// Indexes `PurchaseRecord`s into on-device Spotlight so a system search for
/// a product name, merchant, room, tag, or serial number — or text lifted
/// from a receipt's OCR — surfaces the record and jumps straight to it (see
/// `AppShellView`'s `.onContinueUserActivity(CSSearchableItemActionType)`).
///
/// Three explicit hooks keep the index current as records change locally
/// (`DraftRecordView.saveRecord`, `RecordDetailView.deleteRecord`,
/// `LibraryView.deleteRecord`). Nothing hooks per-field edits or CloudKit-synced
/// changes made on another device — those are covered by `reindexAllDebounced`,
/// called on every app-foreground transition (`AppShellView`).
@MainActor
enum SpotlightIndexer {
    static let domainIdentifier = "records"

    /// Combined OCR text is capped well below Spotlight's per-item limits —
    /// a receipt's full text is rarely useful beyond the first page or two.
    static let maxTextContentBytes = 4096

    /// Trust toggle backing key — Settings → "Your data" → "Show records in
    /// iOS search" (default on). Read fresh on every call (not cached) since
    /// it's cheap and can change between a debounce firing and it running.
    private static let indexingEnabledKey = "spotlightIndexingEnabled"

    nonisolated static var indexingEnabled: Bool {
        (UserDefaults.standard.object(forKey: indexingEnabledKey) as? Bool) ?? true
    }

    /// Reindex a single record — call after any save that changes fields
    /// Spotlight surfaces. No-ops when the user has turned Spotlight
    /// indexing off in Settings.
    static func index(_ record: PurchaseRecord, attachments: [Attachment]) {
        guard indexingEnabled else { return }
        let item = searchableItem(for: record, attachments: attachments)
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                AppLogger.error("Spotlight index failed for \(record.id): \(error)", category: "spotlight")
            }
        }
    }

    /// Remove a record from Spotlight after deletion.
    static func deindex(recordID: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [recordID.uuidString]) { error in
            if let error {
                AppLogger.error("Spotlight deindex failed for \(recordID): \(error)", category: "spotlight")
            }
        }
    }

    // MARK: - Full reindex (app foreground)

    private static var reindexTask: Task<Void, Never>?
    private static let debounceInterval: Duration = .seconds(1.5)

    /// Debounced full reindex — coalesces rapid foreground/background flips
    /// into one pass and runs off the render path (the fetch + `Task` hop
    /// happen after the current view update completes).
    static func reindexAllDebounced() {
        reindexTask?.cancel()
        reindexTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            reindexAll()
        }
    }

    /// Full reindex: fetch + `CSSearchableItem` construction happen entirely
    /// off the main actor, in a detached task with its own `ModelContext`
    /// (never the caller's — SwiftData models don't cross actors). Always
    /// deletes the existing "records" domain first, then indexes the fresh
    /// batch in the delete's completion — so a record deleted on another
    /// device and pulled down by CloudKit sync doesn't leave a stale,
    /// unopenable Spotlight entry behind. When the user has turned Spotlight
    /// indexing off, the delete still runs (purging the index) but nothing
    /// gets re-indexed.
    static func reindexAll() {
        Task.detached(priority: .utility) {
            let enabled = indexingEnabled
            let context = ModelContext(PaperTrailModelContainer.shared)
            let items: [CSSearchableItem]
            do {
                let records = try context.fetch(FetchDescriptor<PurchaseRecord>())
                let attachments = try context.fetch(FetchDescriptor<Attachment>())
                let attachmentsByRecord = Dictionary(grouping: attachments) { $0.recordID }
                items = enabled ? records.map { record in
                    searchableItem(for: record, attachments: attachmentsByRecord[record.id] ?? [])
                } : []
            } catch {
                AppLogger.error("Spotlight full reindex fetch failed: \(error)", category: "spotlight")
                return
            }

            CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
                if let error {
                    AppLogger.error("Spotlight domain delete failed: \(error)", category: "spotlight")
                }
                guard enabled, !items.isEmpty else { return }
                CSSearchableIndex.default().indexSearchableItems(items) { error in
                    if let error {
                        AppLogger.error("Spotlight full reindex failed: \(error)", category: "spotlight")
                    } else {
                        AppLogger.info("Spotlight full reindex completed (\(items.count) records)", category: "spotlight")
                    }
                }
            }
        }
    }

    // MARK: - Item construction

    /// `nonisolated` so `reindexAll()`'s detached task can build items
    /// without hopping back to the main actor per record.
    nonisolated private static func searchableItem(for record: PurchaseRecord, attachments: [Attachment]) -> CSSearchableItem {
        let set = CSSearchableItemAttributeSet(contentType: .text)
        set.title = record.productName
        set.contentDescription = contentDescription(for: record)
        set.keywords = keywords(for: record)

        let combinedOCR = attachments.compactMap(\.ocrText).joined(separator: "\n")
        if !combinedOCR.isEmpty {
            set.textContent = truncated(combinedOCR, maxBytes: maxTextContentBytes)
        }

        return CSSearchableItem(uniqueIdentifier: record.id.uuidString, domainIdentifier: domainIdentifier, attributeSet: set)
    }

    nonisolated static func contentDescription(for record: PurchaseRecord) -> String {
        var parts: [String] = []
        if let merchant = record.merchantName, !merchant.isEmpty { parts.append(merchant) }
        if let amount = record.formattedAmount { parts.append(amount) }
        if record.warrantyExpiryDate != nil { parts.append(record.warrantyStatus.label) }
        return parts.joined(separator: " · ")
    }

    nonisolated static func keywords(for record: PurchaseRecord) -> [String] {
        var keywords = record.tags
        if let category = record.category, !category.isEmpty { keywords.append(category) }
        if let serial = record.serialNumber, !serial.isEmpty { keywords.append(serial) }
        if let room = record.room, !room.isEmpty { keywords.append(room) }
        return keywords
    }

    /// Truncates `text` to at most `maxBytes` UTF-8 bytes without splitting a
    /// multi-byte character. Pure and UIKit-free so it's directly unit-testable
    /// (marked `nonisolated` — it touches no actor-isolated state — so tests
    /// don't need to hop to the main actor to call it).
    nonisolated static func truncated(_ text: String, maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var result = text
        while result.utf8.count > maxBytes {
            result.removeLast()
        }
        return result
    }
}
