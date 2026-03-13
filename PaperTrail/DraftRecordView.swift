import SwiftUI

struct DraftRecordView: View {
    @Environment(PurchaseRecordStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let seedType: AttachmentType
    let seededAttachment: Attachment?
    let seededOCR: OCRExtractionResult?

    @State private var productName: String
    @State private var merchantName: String
    @State private var notes: String
    @State private var purchaseDate = Date()
    @State private var includeWarranty = false
    @State private var warrantyExpiryDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now

    init(seedType: AttachmentType, seededAttachment: Attachment? = nil, seededOCR: OCRExtractionResult? = nil) {
        self.seedType = seedType
        self.seededAttachment = seededAttachment
        self.seededOCR = seededOCR
        _productName = State(initialValue: seededOCR?.suggestedProductName ?? "")
        _merchantName = State(initialValue: seededOCR?.suggestedMerchantName ?? "")
        _notes = State(initialValue: seededOCR?.suggestedNotes ?? "")
    }

    var body: some View {
        Form {
            if let seededOCR, seededOCR.recognizedText.isEmpty == false {
                Section("OCR draft") {
                    Text(seededOCR.recognizedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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
        let attachment = seededAttachment ?? Attachment(type: seedType, localFilename: "placeholder-\(seedType.rawValue).jpg")
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
        DraftRecordView(seedType: .receipt, seededAttachment: .preview, seededOCR: .empty)
            .environment(PurchaseRecordStore())
    }
}
