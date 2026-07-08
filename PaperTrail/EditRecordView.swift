import SwiftUI
import SwiftData

struct EditRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var record: PurchaseRecord
    @Query private var allAttachments: [Attachment]
    @Query private var allRecords: [PurchaseRecord]

    @State private var productName: String
    @State private var merchantName: String
    @State private var notes: String
    @State private var purchaseDate: Date
    @State private var includeWarranty: Bool
    @State private var warrantyExpiryDate: Date
    @State private var returnWindowDays: Int?
    @State private var amountText: String
    @State private var currency: String
    @State private var category: String
    @State private var room: String
    @State private var tagsText: String
    @State private var serialNumber: String
    @State private var coverageSummary: String
    @State private var isRegistered: Bool

    private var attachments: [Attachment] {
        allAttachments.filter { $0.recordID == record.id }
    }

    init(record: PurchaseRecord) {
        self.record = record
        _productName = State(initialValue: record.productName)
        _merchantName = State(initialValue: record.merchantName ?? "")
        _notes = State(initialValue: record.notes ?? "")
        _purchaseDate = State(initialValue: record.purchaseDate ?? .now)
        _includeWarranty = State(initialValue: record.warrantyExpiryDate != nil)
        _warrantyExpiryDate = State(initialValue: record.warrantyExpiryDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
        _returnWindowDays = State(initialValue: record.returnWindowDays)

        if let amount = record.amount {
            _amountText = State(initialValue: String(format: "%.2f", amount))
        } else {
            _amountText = State(initialValue: "")
        }
        _currency = State(initialValue: record.currency ?? "SGD")
        _category = State(initialValue: record.category ?? "")
        _room = State(initialValue: record.room ?? "")
        _tagsText = State(initialValue: record.tags.joined(separator: ", "))
        _serialNumber = State(initialValue: record.serialNumber ?? "")
        _coverageSummary = State(initialValue: record.coverageSummary ?? "")
        _isRegistered = State(initialValue: record.isRegistered)
    }

    var body: some View {
        Form {
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
                Toggle("Warranty expiry", isOn: $includeWarranty)
                if includeWarranty {
                    DatePicker("Warranty expires", selection: $warrantyExpiryDate, displayedComponents: .date)
                }
            }

            Section("Return window") {
                ReturnWindowPicker(returnWindowDays: $returnWindowDays)
            }

            Section("Proof & coverage") {
                TextField("Serial number", text: $serialNumber)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                TextField("Covers (e.g. Parts & labor)", text: $coverageSummary)
                Toggle("Registered with manufacturer", isOn: $isRegistered)
            }

            Section("Organization") {
                TextField("Category (e.g. Electronics, Kitchen)", text: $category)
                LabeledContent("Room") {
                    RoomPicker(room: $room, suggestions: RoomOptions.suggestions(existing: allRecords.compactMap(\.room)))
                }
                TextField("Tags (comma separated)", text: $tagsText)
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
            }

            Section("Attachments (\(attachments.count))") {
                if attachments.isEmpty {
                    Text("No attachments")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(attachments) { attachment in
                        HStack {
                            if let image = attachment.image {
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
        record.notes = notes.isEmpty ? nil : notes
        record.amount = Double(amountText.replacingOccurrences(of: ",", with: ""))
        record.currency = currency
        record.category = category.isEmpty ? nil : category
        record.room = room.isEmpty ? nil : room
        record.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        record.serialNumber = serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        record.coverageSummary = coverageSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : coverageSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        record.isRegistered = isRegistered
        record.updatedAt = .now

        // Update warranty & notifications
        let oldWarranty = record.warrantyExpiryDate
        record.warrantyExpiryDate = includeWarranty ? warrantyExpiryDate : nil

        let reminderPrefs = ReminderSettings.shared
        if includeWarranty, reminderPrefs.warrantyRemindersEnabled {
            // Reschedule if warranty date changed
            if oldWarranty != warrantyExpiryDate || !record.warrantyNotificationScheduled {
                record.warrantyNotificationScheduled = true
                NotificationManager.shared.scheduleWarrantyReminders(for: record, leadDays: reminderPrefs.warrantyLeadTime.days)
            }
        } else {
            record.warrantyNotificationScheduled = false
            NotificationManager.shared.removeWarrantyReminders(for: record)
        }

        // Return window & its reminders — mirrors the warranty block above exactly.
        let oldReturnWindowDays = record.returnWindowDays
        record.returnWindowDays = returnWindowDays

        if returnWindowDays != nil, reminderPrefs.returnWindowRemindersEnabled {
            // Reschedule if the window changed
            if oldReturnWindowDays != returnWindowDays || !record.returnWindowNotificationScheduled {
                record.returnWindowNotificationScheduled = true
                NotificationManager.shared.scheduleReturnWindowReminder(for: record)
            }
        } else {
            record.returnWindowNotificationScheduled = false
            NotificationManager.shared.removeReturnWindowReminder(for: record)
        }

        dismiss()
    }
}

#Preview {
    NavigationStack {
        Text("Preview requires SwiftData context")
    }
}
