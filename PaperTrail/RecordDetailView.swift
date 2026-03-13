import SwiftUI

struct RecordDetailView: View {
    @Environment(PurchaseRecordStore.self) private var store
    let record: PurchaseRecord

    private var currentRecord: PurchaseRecord {
        store.records.first(where: { $0.id == record.id }) ?? record
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(currentRecord.productName)
                        .font(.title3.bold())

                    if let merchantName = currentRecord.merchantName {
                        Label(merchantName, systemImage: "storefront")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Purchase") {
                if let purchaseDate = currentRecord.purchaseDate {
                    LabeledContent("Purchased") {
                        Text(purchaseDate, format: .dateTime.day().month().year())
                    }
                }

                if let warrantyExpiryDate = currentRecord.warrantyExpiryDate {
                    LabeledContent("Warranty until") {
                        Text(warrantyExpiryDate, format: .dateTime.day().month().year())
                    }
                }
            }

            if let notes = currentRecord.notes {
                Section("Notes") {
                    Text(notes)
                }
            }

            Section("Attachments") {
                ForEach(currentRecord.attachments) { attachment in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(attachment.type.rawValue.capitalized)
                            .font(.headline)
                        Text(attachment.localFilename)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let ocrText = attachment.ocrText {
                            Text(ocrText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    EditRecordView(record: currentRecord)
                } label: {
                    Text("Edit")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecordDetailView(record: .preview)
            .environment(PurchaseRecordStore())
    }
}
