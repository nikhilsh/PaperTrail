import SwiftUI

struct RecordDetailView: View {
    let record: PurchaseRecord

    var body: some View {
        List {
            Section("Purchase") {
                LabeledContent("Product", value: record.productName)

                if let merchantName = record.merchantName {
                    LabeledContent("Store", value: merchantName)
                }

                if let purchaseDate = record.purchaseDate {
                    LabeledContent("Purchased") {
                        Text(purchaseDate, format: .dateTime.day().month().year())
                    }
                }

                if let warrantyExpiryDate = record.warrantyExpiryDate {
                    LabeledContent("Warranty until") {
                        Text(warrantyExpiryDate, format: .dateTime.day().month().year())
                    }
                }
            }

            if let notes = record.notes {
                Section("Notes") {
                    Text(notes)
                }
            }

            Section("Attachments") {
                ForEach(record.attachments) { attachment in
                    VStack(alignment: .leading, spacing: 4) {
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
        .navigationTitle(record.productName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    EditRecordView(record: record)
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
    }
}
