import SwiftUI
import SwiftData

struct DraftRecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager

    let seedType: AttachmentType
    let seededAttachments: [Attachment]
    let seededOCR: OCRExtractionResult?

    @State private var productName: String
    @State private var merchantName: String
    @State private var notes: String
    @State private var purchaseDate: Date
    @State private var includeWarranty = false
    @State private var warrantyExpiryDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var amountText: String
    @State private var currency: String
    @State private var category: String = ""
    @State private var tagsText: String = ""

    init(seedType: AttachmentType, seededAttachments: [Attachment] = [], seededOCR: OCRExtractionResult? = nil) {
        self.seedType = seedType
        self.seededAttachments = seededAttachments
        self.seededOCR = seededOCR
        _productName = State(initialValue: seededOCR?.suggestedProductName ?? "")
        _merchantName = State(initialValue: seededOCR?.suggestedMerchantName ?? "")
        _notes = State(initialValue: seededOCR?.suggestedNotes ?? "")
        _purchaseDate = State(initialValue: seededOCR?.suggestedPurchaseDate ?? .now)

        if let amount = seededOCR?.suggestedAmount {
            _amountText = State(initialValue: String(format: "%.2f", amount))
        } else {
            _amountText = State(initialValue: "")
        }
        _currency = State(initialValue: seededOCR?.suggestedCurrency ?? "SGD")
        _category = State(initialValue: seededOCR?.suggestedCategory ?? "")

        // If Foundation Models extracted a warranty duration, pre-fill the warranty toggle and date.
        if let months = seededOCR?.suggestedWarrantyDurationMonths,
           let purchaseDate = seededOCR?.suggestedPurchaseDate,
           let expiryDate = Calendar.current.date(byAdding: .month, value: months, to: purchaseDate) {
            _includeWarranty = State(initialValue: true)
            _warrantyExpiryDate = State(initialValue: expiryDate)
        }
    }

    var body: some View {
        Form {
            if let seededOCR, !seededOCR.recognizedText.isEmpty {
                Section("Extracted text") {
                    Text(seededOCR.recognizedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)

                    if let source = seededOCR.extractionSource {
                        HStack(spacing: 6) {
                            Image(systemName: source == .foundationModel ? "cpu" : "text.magnifyingglass")
                                .font(.caption2)
                            Text(source == .foundationModel ? "Extracted with Apple Intelligence" : "Extracted with pattern matching")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    }
                }
            }

            if !seededAttachments.isEmpty {
                Section("Scanned pages") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(seededAttachments) { attachment in
                                if let image = attachment.image {
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

            Section("Amount") {
                HStack {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        Text("SGD").tag("SGD")
                        Text("USD").tag("USD")
                        Text("MYR").tag("MYR")
                        Text("EUR").tag("EUR")
                        Text("GBP").tag("GBP")
                        Text("JPY").tag("JPY")
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("Warranty") {
                Toggle("Add warranty expiry", isOn: $includeWarranty)
                if includeWarranty {
                    DatePicker("Warranty expires", selection: $warrantyExpiryDate, displayedComponents: .date)
                }
            }

            Section("Organization") {
                TextField("Category (e.g. Electronics, Kitchen)", text: $category)
                TextField("Tags (comma separated)", text: $tagsText)
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
        let parsedAmount = Double(amountText.replacingOccurrences(of: ",", with: ""))
        let parsedTags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let record = PurchaseRecord(
            productName: productName,
            merchantName: merchantName.isEmpty ? nil : merchantName,
            purchaseDate: purchaseDate,
            warrantyExpiryDate: includeWarranty ? warrantyExpiryDate : nil,
            notes: notes.isEmpty ? nil : notes,
            amount: parsedAmount,
            currency: currency,
            category: category.isEmpty ? nil : category,
            tags: parsedTags
        )

        modelContext.insert(record)

        for attachment in seededAttachments {
            attachment.recordID = record.id
            modelContext.insert(attachment)
        }

        // Schedule warranty notifications if applicable
        if includeWarranty {
            record.warrantyNotificationScheduled = true
            NotificationManager.shared.scheduleWarrantyReminders(for: record)
        }

        // Upload attachment images to CloudKit in the background
        let attachmentsToUpload = seededAttachments.map {
            AttachmentSyncInfo(id: $0.id, localFilename: $0.localFilename)
        }
        Task {
            for info in attachmentsToUpload {
                await cloudImageSync.upload(attachmentID: info.id, localFilename: info.localFilename)
            }
        }

        dismiss()
    }
}

#Preview {
    NavigationStack {
        DraftRecordView(seedType: .receipt)
    }
    .environmentObject(CloudImageSyncManager.shared)
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
