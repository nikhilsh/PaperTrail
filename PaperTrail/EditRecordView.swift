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
    @State private var showBarcodeScanner = false
    /// Coverage Passport (v2 design wave, W2) "What's covered" lines.
    @State private var coverageLines: [CoverageLine]
    @State private var newCoverageLineLabel = ""
    @State private var newCoverageLineCovered = true
    /// v3 `multiCoverage` (docs/design-v3/V3_BRIEF.md §2) additions to the
    /// "add coverage line" mini-form — only surfaced in the UI when the flag
    /// is on (see `coverageLineDetailEditor`/the add-row below).
    @State private var newCoverageLineKind: CoverageLineKind?
    @State private var newCoverageLineStartDate: Date?
    @State private var newCoverageLineEndDate: Date?

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
        _currency = State(initialValue: record.currency ?? PTCurrency.deviceDefault)
        _category = State(initialValue: record.category ?? "")
        _room = State(initialValue: record.room ?? "")
        _tagsText = State(initialValue: record.tags.joined(separator: ", "))
        _serialNumber = State(initialValue: record.serialNumber ?? "")
        _coverageSummary = State(initialValue: record.coverageSummary ?? "")
        _isRegistered = State(initialValue: record.isRegistered)
        _coverageLines = State(initialValue: record.coverageLines)
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
                HStack {
                    TextField("Serial number", text: $serialNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    if BarcodeScannerView.isSupported {
                        Button {
                            showBarcodeScanner = true
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                TextField("Covers (e.g. Parts & labor)", text: $coverageSummary)
                Toggle("Registered with manufacturer", isOn: $isRegistered)
            }

            Section("Coverage passport — what's covered") {
                ForEach($coverageLines) { $line in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Coverage line", text: $line.label)
                            Toggle("", isOn: $line.covered).labelsHidden()
                        }
                        if FeatureFlags.isOn(.multiCoverage) {
                            coverageLineDetailEditor(line: $line)
                        }
                    }
                }
                .onDelete { coverageLines.remove(atOffsets: $0) }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Add coverage line (e.g. Accidental damage)", text: $newCoverageLineLabel)
                        Toggle("", isOn: $newCoverageLineCovered).labelsHidden()
                        Button {
                            addCoverageLine()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(newCoverageLineLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if FeatureFlags.isOn(.multiCoverage) {
                        Picker("Kind", selection: $newCoverageLineKind) {
                            Text("None").tag(CoverageLineKind?.none)
                            ForEach(CoverageLineKind.allCases) { kind in
                                Text(kind.label).tag(CoverageLineKind?.some(kind))
                            }
                        }
                        .pickerStyle(.menu)
                        optionalDateRow(title: "Starts", date: $newCoverageLineStartDate)
                        optionalDateRow(title: "Ends", date: $newCoverageLineEndDate)
                    }
                }
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
        .ptKeyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveEdits()
                }
                .fontWeight(.semibold)
                .disabled(productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $showBarcodeScanner) {
            BarcodeScannerSheet { payload in
                serialNumber = payload
            }
        }
    }

    /// v3 `multiCoverage` per-line kind picker + optional start/end dates —
    /// extends Wave C's minimal editor per docs/design-v3/V3_BRIEF.md §2.
    /// Only reachable when the flag is on (both call sites gate on it).
    private func coverageLineDetailEditor(line: Binding<CoverageLine>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Kind", selection: Binding(
                get: { line.wrappedValue.kindEnum },
                set: { line.wrappedValue.kindEnum = $0 }
            )) {
                Text("None").tag(CoverageLineKind?.none)
                ForEach(CoverageLineKind.allCases) { kind in
                    Text(kind.label).tag(CoverageLineKind?.some(kind))
                }
            }
            .pickerStyle(.menu)

            optionalDateRow(title: "Starts", date: Binding(
                get: { line.wrappedValue.startDate },
                set: { line.wrappedValue.startDate = $0 }
            ))
            optionalDateRow(title: "Ends", date: Binding(
                get: { line.wrappedValue.endDate },
                set: { line.wrappedValue.endDate = $0 }
            ))
        }
    }

    /// A toggle that, when on, reveals a date picker — the same
    /// present-or-absent pattern `includeWarranty`/`warrantyExpiryDate`
    /// already use above, generalized for `Binding<Date?>`.
    private func optionalDateRow(title: String, date: Binding<Date?>) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { date.wrappedValue != nil },
                set: { isOn in date.wrappedValue = isOn ? (date.wrappedValue ?? .now) : nil }
            ))
            if date.wrappedValue != nil {
                DatePicker(
                    "",
                    selection: Binding(get: { date.wrappedValue ?? .now }, set: { date.wrappedValue = $0 }),
                    displayedComponents: .date
                )
                .labelsHidden()
            }
        }
    }

    private func addCoverageLine() {
        let trimmed = newCoverageLineLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coverageLines.append(CoverageLine(
            label: trimmed,
            covered: newCoverageLineCovered,
            startDate: newCoverageLineStartDate,
            endDate: newCoverageLineEndDate,
            kind: newCoverageLineKind?.rawValue
        ))
        newCoverageLineLabel = ""
        newCoverageLineCovered = true
        newCoverageLineKind = nil
        newCoverageLineStartDate = nil
        newCoverageLineEndDate = nil
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
        record.coverageLines = coverageLines
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

        // Coverage-line reminders (v3 multiCoverage, docs/design-v3/V3_BRIEF.md
        // §3) — reschedule on every save, mirroring the warranty/return-window
        // blocks above, and now also respecting the same
        // `warrantyRemindersEnabled` toggle those use (§6 coverage reminders
        // discipline — coverage lines shouldn't keep notifying after the
        // user turned warranty reminders off). When either the flag or the
        // toggle is off, explicitly clear any reminders scheduled from
        // before — `CoverageReminders.reschedule` no-ops entirely when the
        // flag is off (it wouldn't even clear stale requests), so this is
        // the one place that has to do it.
        let recordIDForCoverage = record.id
        if FeatureFlags.isOn(.multiCoverage), reminderPrefs.warrantyRemindersEnabled {
            let leadDays = reminderPrefs.warrantyLeadTime.days
            Task {
                await CoverageReminders.reschedule(for: record, leadDays: leadDays)
            }
        } else {
            Task {
                await CoverageReminders.removeReminders(for: recordIDForCoverage)
            }
        }

        dismiss()
    }
}

#Preview {
    NavigationStack {
        Text("Preview requires SwiftData context")
    }
}
