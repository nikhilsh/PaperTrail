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

    /// Reindex a single record — call after any save that changes fields
    /// Spotlight surfaces.
    static func index(_ record: PurchaseRecord, attachments: [Attachment]) {
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
    static func reindexAllDebounced(modelContext: ModelContext) {
        reindexTask?.cancel()
        reindexTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            reindexAll(modelContext: modelContext)
        }
    }

    static func reindexAll(modelContext: ModelContext) {
        do {
            let records = try modelContext.fetch(FetchDescriptor<PurchaseRecord>())
            let attachments = try modelContext.fetch(FetchDescriptor<Attachment>())
            let attachmentsByRecord = Dictionary(grouping: attachments) { $0.recordID }
            let items = records.map { record in
                searchableItem(for: record, attachments: attachmentsByRecord[record.id] ?? [])
            }
            guard !items.isEmpty else { return }
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error {
                    AppLogger.error("Spotlight full reindex failed: \(error)", category: "spotlight")
                } else {
                    AppLogger.info("Spotlight full reindex completed (\(items.count) records)", category: "spotlight")
                }
            }
        } catch {
            AppLogger.error("Spotlight full reindex fetch failed: \(error)", category: "spotlight")
        }
    }

    // MARK: - Item construction

    private static func searchableItem(for record: PurchaseRecord, attachments: [Attachment]) -> CSSearchableItem {
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
