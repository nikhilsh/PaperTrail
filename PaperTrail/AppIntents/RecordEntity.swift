//
//  RecordEntity.swift
//  PaperTrail
//
//  AppEntity wrapper around PurchaseRecord so Siri/Shortcuts can pick a
//  specific item. READ-ONLY: this whole App Intents surface only fetches
//  records via ModelContext — nothing here ever inserts, updates, or deletes.
//

import AppIntents
import Foundation
import SwiftData

struct RecordEntity: AppEntity, Identifiable {
    /// `PurchaseRecord.id` — a stable, non-optional `UUID` stored property —
    /// is the natural key here, not SwiftData's `PersistentIdentifier`. The
    /// persistent identifier isn't guaranteed stable across CloudKit sync
    /// merges, and Shortcuts/Siri persist an entity's `id` across app
    /// launches (donated shortcuts, widgets, "run again"), so it needs to
    /// survive a record round-tripping through iCloud.
    let id: UUID
    let productName: String
    let merchantName: String?

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Item"
    static var defaultQuery = RecordEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        if let merchantName, !merchantName.trimmingCharacters(in: .whitespaces).isEmpty {
            DisplayRepresentation(title: "\(productName) — \(merchantName)")
        } else {
            DisplayRepresentation(title: "\(productName)")
        }
    }

    init(record: PurchaseRecord) {
        self.id = record.id
        self.productName = record.productName
        self.merchantName = record.merchantName
    }
}

/// Looks records up by id (restoring a donated shortcut / widget configuration)
/// or by a substring of product/merchant name (Siri disambiguation, typing in
/// the Shortcuts app). Every fetch goes through the app's single shared
/// `ModelContainer` — see `PaperTrailModelContainer` in PaperTrailApp.swift —
/// so App Intents never opens a second store configuration.
struct RecordEntityQuery: EntityStringQuery {

    @MainActor
    func entities(for identifiers: [RecordEntity.ID]) async throws -> [RecordEntity] {
        let wanted = Set(identifiers)
        return try fetchAllRecords()
            .filter { wanted.contains($0.id) }
            .map(RecordEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [RecordEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return try await suggestedEntities() }

        return try fetchAllRecords()
            .filter {
                $0.productName.lowercased().contains(needle)
                    || ($0.merchantName?.lowercased().contains(needle) ?? false)
            }
            .sorted { $0.productName.localizedStandardCompare($1.productName) == .orderedAscending }
            .map(RecordEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [RecordEntity] {
        var descriptor = FetchDescriptor<PurchaseRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        let context = ModelContext(PaperTrailModelContainer.shared)
        return try context.fetch(descriptor).map(RecordEntity.init)
    }

    @MainActor
    private func fetchAllRecords() throws -> [PurchaseRecord] {
        let context = ModelContext(PaperTrailModelContainer.shared)
        return try context.fetch(FetchDescriptor<PurchaseRecord>())
    }
}
