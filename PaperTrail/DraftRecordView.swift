import SwiftUI

struct DraftRecordView: View {
    @EnvironmentObject private var store: PurchaseRecordStore
    @Environment(\.dismiss) private var dismiss

    let seedType: AttachmentType

    @State private var productName = ""
    @State private var merchantName = ""
    @State private var notes = ""
    @State private var purchaseDate = Date()
    @State private var includeWarranty = false
    @State private var warrantyExpiryDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now

    var body: some View {
        Form {
            Section("Details") {
                TextField("Product name", text: $productName)
                TextField("Store", text: $merchantName)
                DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)
            }

            Section("Warranty") {
                Toggle("Add warranty expiry", isOn: $includeWarranty)
                if includeWarranty {
                    DatePicker("Warranty expires", selection: $warrantyExpiryDate, displayedComponents: .date)
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
            }
        }
        .navigationTitle("Draft Record")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveRecord()
                }
                .disabled(productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func saveRecord() {
        let attachment = Attachment(type: seedType, localFilename: "placeholder-\(seedType.rawValue).jpg")
        let record = PurchaseRecord(
            productName: productName,
            merchantName: merchantName.isEmpty ? nil : merchantName,
            purchaseDate: purchaseDate,
            warrantyExpiryDate: includeWarranty ? warrantyExpiryDate : nil,
            notes: notes.isEmpty ? nil : notes,
            attachments: [attachment]
        )

        store.add(record)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        DraftRecordView(seedType: .receipt)
            .environmentObject(PurchaseRecordStore())
    }
}
