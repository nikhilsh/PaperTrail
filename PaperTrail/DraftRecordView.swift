import SwiftUI
import SwiftData

struct DraftRecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let seedType: AttachmentType
    let seededAttachments: [Attachment]
    let seededOCR: OCRExtractionResult?

    @State private var productName: String
    @State private var merchantName: String
    @State private var notes: String
    @State private var purchaseDate: Date
    @State private var includeWarranty = false
    @State private var warrantyExpiryDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now

    init(seedType: AttachmentType, seededAttachments: [Attachment] = [], seededOCR: OCRExtractionResult? = nil) {
        self.seedType = seedType
        self.seededAttachments = seededAttachments
        self.seededOCR = seededOCR
        _productName = State(initialValue: seededOCR?.suggestedProductName ?? "")
        _merchantName = State(initialValue: seededOCR?.suggestedMerchantName ?? "")
        _notes = State(initialValue: seededOCR?.suggestedNotes ?? "")
        _purchaseDate = State(initialValue: seededOCR?.suggestedPurchaseDate ?? .now)
    }

    var body: some View {
        Form {
            if let seededOCR, !seededOCR.recognizedText.isEmpty {
                Section("Extracted text") {
                    Text(seededOCR.recognizedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                }
            }

            if !seededAttachments.isEmpty {
                Section("Scanned pages") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(seededAttachments) { attachment in
                                if let image = ImageStorageManager.load(attachment.localFilename) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
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
        .navigationTitle("New Record")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveRecord()
                }
                .fontWeight(.semibold)
                .disabled(productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func saveRecord() {
        let record = PurchaseRecord(
            productName: productName,
            merchantName: merchantName.isEmpty ? nil : merchantName,
            purchaseDate: purchaseDate,
            warrantyExpiryDate: includeWarranty ? warrantyExpiryDate : nil,
            notes: notes.isEmpty ? nil : notes
        )

        // Link attachments to the record
        for attachment in seededAttachments {
            attachment.record = record
            record.attachments.append(attachment)
        }

        modelContext.insert(record)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        DraftRecordView(seedType: .receipt)
    }
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
