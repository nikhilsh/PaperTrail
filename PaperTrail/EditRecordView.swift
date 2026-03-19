import SwiftUI
import SwiftData

struct EditRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var record: PurchaseRecord

    @State private var productName: String
    @State private var merchantName: String
    @State private var notes: String
    @State private var purchaseDate: Date
    @State private var includeWarranty: Bool
    @State private var warrantyExpiryDate: Date

    init(record: PurchaseRecord) {
        self.record = record
        _productName = State(initialValue: record.productName)
        _merchantName = State(initialValue: record.merchantName ?? "")
        _notes = State(initialValue: record.notes ?? "")
        _purchaseDate = State(initialValue: record.purchaseDate ?? .now)
        _includeWarranty = State(initialValue: record.warrantyExpiryDate != nil)
        _warrantyExpiryDate = State(initialValue: record.warrantyExpiryDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Product name", text: $productName)
                TextField("Store", text: $merchantName)
                DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)
            }

            Section("Warranty") {
                Toggle("Warranty expiry", isOn: $includeWarranty)
                if includeWarranty {
                    DatePicker("Warranty expires", selection: $warrantyExpiryDate, displayedComponents: .date)
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
            }

            Section("Attachments (\(record.attachments.count))") {
                if record.attachments.isEmpty {
                    Text("No attachments")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(record.attachments) { attachment in
                        HStack {
                            if let image = ImageStorageManager.load(attachment.localFilename) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            VStack(alignment: .leading) {
                                Text(attachment.type.rawValue.capitalized)
                                    .font(.subheadline.weight(.medium))
                                Text(attachment.localFilename)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Edit Record")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveEdits()
                }
                .fontWeight(.semibold)
                .disabled(productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func saveEdits() {
        record.productName = productName
        record.merchantName = merchantName.isEmpty ? nil : merchantName
        record.purchaseDate = purchaseDate
        record.warrantyExpiryDate = includeWarranty ? warrantyExpiryDate : nil
        record.notes = notes.isEmpty ? nil : notes
        record.updatedAt = .now
        dismiss()
    }
}

#Preview {
    NavigationStack {
        Text("Preview requires SwiftData context")
    }
}
