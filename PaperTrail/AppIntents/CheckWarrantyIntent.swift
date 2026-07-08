//
//  CheckWarrantyIntent.swift
//  PaperTrail
//
//  "Is my LG Washer under warranty?" — READ-ONLY: fetches the record and
//  speaks its warranty status. Never writes anything back.
//

import AppIntents
import SwiftData
import SwiftUI

struct RecordNoLongerAvailableError: LocalizedError {
    var errorDescription: String? { "That item is no longer in PaperTrail." }
}

struct CheckWarrantyIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Warranty"
    static var description = IntentDescription(
        "Ask whether an item you've saved in PaperTrail is still under warranty."
    )

    @Parameter(title: "Item")
    var record: RecordEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check warranty for \(\.$record)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = ModelContext(PaperTrailModelContainer.shared)
        let recordID = record.id
        let descriptor = FetchDescriptor<PurchaseRecord>()
        guard let match = try context.fetch(descriptor).first(where: { $0.id == recordID }) else {
            throw RecordNoLongerAvailableError()
        }

        let sentence = WarrantySpeech.statusSentence(
            productName: match.productName,
            expiryDate: match.warrantyExpiryDate
        )

        return .result(
            dialog: IntentDialog(stringLiteral: sentence),
            view: WarrantySnippetView(record: match)
        )
    }
}

/// Small card shown alongside the spoken answer — product, merchant, and a
/// status-colored badge. Reuses `ptGlyph` / `WarrantyStatus.label`
/// (Design/PTPresentation.swift, PurchaseRecord.swift) so the wording matches
/// the rest of the app instead of drifting into its own copy.
struct WarrantySnippetView: View {
    let record: PurchaseRecord

    private var statusColor: Color {
        switch record.warrantyStatus {
        case .active: .green
        case .expiringSoon: .orange
        case .expired: .red
        case .unknown: .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ptGlyph(category: record.category, productName: record.productName))
                .font(.system(size: 20))
                .foregroundStyle(statusColor)
                .frame(width: 40, height: 40)
                .background(statusColor.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(record.productName)
                    .font(.headline)
                if let merchant = record.merchantName, !merchant.isEmpty {
                    Text(merchant)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(record.warrantyStatus.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}
