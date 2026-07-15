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
        let record: PurchaseRecord
        let name: String
        let merchantName: String?
        let purchaseDate: Date?
        let amount: Double?
        let currency: String?
        let estimatedCurrentValue: Double?
        let serialNumber: String?
        let warrantyStatus: WarrantyStatus
        /// The attachment to draw a thumbnail from at render time: the
        /// record's `productImageAttachmentID` attachment if it exists among
        /// the record's attachments, else the first attachment for the
        /// record (if any). `nil` if the record has no attachments at all.
        let thumbnailAttachment: Attachment?
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
    }

    /// The room name used for records with a nil or blank `room`.
    static let unfiledRoomName = "Unfiled"
    /// Currency assumed for records that don't specify one (mirrors
    /// `PurchaseRecord.formattedAmount`'s fallback).
    static let defaultCurrency = "SGD"

    static func build(records: [PurchaseRecord], attachments: [Attachment], asOf: Date = .now) -> Report {
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
                record: record,
                name: record.productName,
                merchantName: record.merchantName,
                purchaseDate: record.purchaseDate,
                amount: record.amount,
                currency: record.currency,
                estimatedCurrentValue: estimated,
                serialNumber: record.serialNumber,
                warrantyStatus: record.warrantyStatus,
                thumbnailAttachment: thumbnailAttachment(for: record, attachments: recordAttachments)
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

        let allItems = sections.flatMap(\.items)
        return Report(
            sections: sections,
            totalItemCount: allItems.count,
            grandPurchaseTotalsByCurrency: sumByCurrency(allItems, \.amount),
            grandEstimatedTotalsByCurrency: sumByCurrency(allItems, \.estimatedCurrentValue),
            generatedAt: asOf
        )
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

    /// Sums `keyPath` across `items`, grouped by currency (falling back to
    /// `defaultCurrency` for items with no currency set) — never summed
    /// across different currencies. Rounded to 2dp per currency.
    private static func sumByCurrency(_ items: [Item], _ keyPath: KeyPath<Item, Double?>) -> [String: Double] {
        var totals: [String: Double] = [:]
        for item in items {
            guard let value = item[keyPath: keyPath] else { continue }
            let currency = item.currency ?? defaultCurrency
            totals[currency, default: 0] += value
        }
        for (currency, total) in totals {
            totals[currency] = (total * 100).rounded() / 100
        }
        return totals
    }
}
