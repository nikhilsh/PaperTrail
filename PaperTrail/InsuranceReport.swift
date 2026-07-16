import Foundation

/// Groups and totals purchase records into the shape the Home Inventory
/// Report renders: rooms (alphabetical, "Unfiled" for nil/empty), items
/// within a room sorted by amount descending, and per-currency subtotals
/// that are never summed across currencies.
///
/// v1 scope: the caller passes LOCAL records only (household shared-in
/// records — which live as a separate model, not `PurchaseRecord` — are a
/// follow-up; see the PR description).
///
/// Pure and free of SwiftData/UIKit access beyond reading model properties,
/// so it's directly unit-testable.
nonisolated enum InsuranceReport {

    struct Item {
        let name: String
        let merchantName: String?
        let purchaseDate: Date?
        let amount: Double?
        let currency: String?
        let estimatedCurrentValue: Double?
        let serialNumber: String?
        let warrantyStatus: WarrantyStatus
        /// The on-disk filename (`Attachment.localFilename`) of the attachment
        /// to draw a thumbnail from at render time: the record's
        /// `productImageAttachmentID` attachment if it exists among the
        /// record's attachments, else the first attachment for the record (if
        /// any). `nil` if the record has no attachments at all.
        ///
        /// A plain `String` rather than the `Attachment` model itself — this
        /// `Item` is handed to `InsuranceReportPDF.generate`, which runs off
        /// the main actor on a detached task and must not touch SwiftData
        /// models.
        let thumbnailFilename: String?
    }

    struct RoomSection {
        let name: String
        let items: [Item]
        /// Sum of `amount` for items in this room, keyed by currency code.
        let purchaseTotalsByCurrency: [String: Double]
        /// Sum of `estimatedCurrentValue` for items in this room, keyed by currency code.
        let estimatedTotalsByCurrency: [String: Double]
    }

    struct Report {
        let sections: [RoomSection]
        let totalItemCount: Int
        let grandPurchaseTotalsByCurrency: [String: Double]
        let grandEstimatedTotalsByCurrency: [String: Double]
        let generatedAt: Date
        /// True when `build` was asked to restrict to a single room (the
        /// PaperTrail Plus free-preview gate — see `ExportView`). Drives the
        /// "Free preview" cover-page line in `InsuranceReportPDF`. Defaults
        /// to `false` so every existing call site stays unaffected.
        var isPlusPreview: Bool = false
    }

    /// The room name used for records with a nil or blank `room`.
    static let unfiledRoomName = "Unfiled"
    /// Bucket key for totals summed from items with no `currency` set. Kept
    /// separate from every real currency code so these amounts are never
    /// fabricated into (and never summed into) an actual currency's total —
    /// the renderer displays this bucket as a bare number, no symbol.
    static let unspecifiedCurrency = "Unspecified"

    /// - Parameter restrictToHighestValueRoom: PaperTrail Plus free-preview
    ///   gate (docs/MONETIZATION.md — "Insurance-Ready Report... Free tier:
    ///   one room"). When `true`, the report is trimmed to the single room
    ///   with the highest total purchase value after grouping — everything
    ///   else about `build` runs unchanged. Defaults to `false`, so every
    ///   existing caller (including all current tests) is unaffected.
    static func build(records: [PurchaseRecord], attachments: [Attachment], asOf: Date = .now, restrictToHighestValueRoom: Bool = false) -> Report {
        let attachmentsByRecord = Dictionary(grouping: attachments, by: { $0.recordID })

        let itemsByRoom: [String: [Item]] = records.reduce(into: [:]) { acc, record in
            let room = normalizedRoom(record.room)
            let recordAttachments = attachmentsByRecord[record.id] ?? []
            let estimated = DepreciationEstimator.estimatedCurrentValue(
                amount: record.amount,
                category: record.category,
                purchaseDate: record.purchaseDate,
                asOf: asOf
            )
            let item = Item(
                name: record.productName,
                merchantName: record.merchantName,
                purchaseDate: record.purchaseDate,
                amount: record.amount,
                currency: record.currency,
                estimatedCurrentValue: estimated,
                serialNumber: record.serialNumber,
                warrantyStatus: record.warrantyStatus,
                thumbnailFilename: thumbnailAttachment(for: record, attachments: recordAttachments)?.localFilename
            )
            acc[room, default: []].append(item)
        }

        let sections: [RoomSection] = itemsByRoom.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { room in
                let items = itemsByRoom[room]!.sorted { (lhs, rhs) in (lhs.amount ?? 0) > (rhs.amount ?? 0) }
                return RoomSection(
                    name: room,
                    items: items,
                    purchaseTotalsByCurrency: sumByCurrency(items, \.amount),
                    estimatedTotalsByCurrency: sumByCurrency(items, \.estimatedCurrentValue)
                )
            }

        let finalSections: [RoomSection]
        if restrictToHighestValueRoom, let topRoom = sections.max(by: { roomTotalValue($0) < roomTotalValue($1) }) {
            finalSections = [topRoom]
        } else {
            finalSections = sections
        }

        let allItems = finalSections.flatMap(\.items)
        return Report(
            sections: finalSections,
            totalItemCount: allItems.count,
            grandPurchaseTotalsByCurrency: sumByCurrency(allItems, \.amount),
            grandEstimatedTotalsByCurrency: sumByCurrency(allItems, \.estimatedCurrentValue),
            generatedAt: asOf,
            isPlusPreview: restrictToHighestValueRoom
        )
    }

    /// Sum of a room's purchase totals across currencies — for RANKING rooms
    /// only (picking the single highest-value room for the free-preview
    /// gate), never displayed: mixing currencies into one number would be
    /// wrong to show a user, but it's a fine tie-breaker heuristic here.
    private static func roomTotalValue(_ section: RoomSection) -> Double {
        section.purchaseTotalsByCurrency.values.reduce(0, +)
    }

    private static func normalizedRoom(_ room: String?) -> String {
        guard let room else { return unfiledRoomName }
        let trimmed = room.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unfiledRoomName : trimmed
    }

    private static func thumbnailAttachment(for record: PurchaseRecord, attachments: [Attachment]) -> Attachment? {
        if let id = record.productImageAttachmentID, let match = attachments.first(where: { $0.id == id }) {
            return match
        }
        return attachments.first
    }

    /// Sums `keyPath` across `items`, grouped by currency (bucketing items
    /// with no currency set under `unspecifiedCurrency`, which never merges
    /// with a real currency's total) — never summed across different
    /// currencies. Rounded to 2dp per currency.
    private static func sumByCurrency(_ items: [Item], _ keyPath: KeyPath<Item, Double?>) -> [String: Double] {
        var totals: [String: Double] = [:]
        for item in items {
            guard let value = item[keyPath: keyPath] else { continue }
            let currency = item.currency ?? unspecifiedCurrency
            totals[currency, default: 0] += value
        }
        for (currency, total) in totals {
            totals[currency] = (total * 100).rounded() / 100
        }
        return totals
    }
}
