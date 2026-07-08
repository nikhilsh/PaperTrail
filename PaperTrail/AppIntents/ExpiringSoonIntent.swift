//
//  ExpiringSoonIntent.swift
//  PaperTrail
//
//  "What's expiring soon in PaperTrail?" — READ-ONLY: summarizes warranties
//  expiring in the next 60 days (mirrors PurchaseRecord.warrantyStatus's own
//  60-day `.expiringSoon` cutoff, so this says the same thing the Warranty
//  tab's "Needs attention" section would show).
//

import AppIntents
import SwiftData

struct ExpiringSoonIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Expiring Soon"
    static var description = IntentDescription(
        "Hear which items' warranties are expiring in the next 60 days."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(PaperTrailModelContainer.shared)
        let all = try context.fetch(FetchDescriptor<PurchaseRecord>())

        let expiringSoon: [(name: String, date: Date)] = all
            .filter { $0.warrantyStatus == .expiringSoon }
            .compactMap { record in
                guard let date = record.warrantyExpiryDate else { return nil }
                return (name: record.productName, date: date)
            }
            .sorted { $0.date < $1.date }

        let sentence = WarrantySpeech.expiringSoonSummary(records: expiringSoon)
        return .result(dialog: IntentDialog(stringLiteral: sentence))
    }
}
