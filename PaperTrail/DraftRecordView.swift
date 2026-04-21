import SwiftUI
import SwiftData

struct DraftRecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @State private var learningContext: MerchantLearningContext?

    let seedType: AttachmentType
    let seededAttachments: [Attachment]
    let seededOCR: OCRExtractionResult?

    /// The structured extraction result preserved for confidence badges and correction logging.
    private let structuredResult: StructuredExtractionResult?

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
    @State private var showExtractionLogSheet = false

    /// Line items extracted from the document, for user selection.
    private let lineItems: [LineItem]
    /// The currently selected line item ID (user picks the main item for the record).
    @State private var selectedItemId: UUID?

    init(seedType: AttachmentType, seededAttachments: [Attachment] = [], seededOCR: OCRExtractionResult? = nil) {
        self.seedType = seedType
        self.seededAttachments = seededAttachments
        self.seededOCR = seededOCR
        self.structuredResult = seededOCR?.structuredResult
        self.lineItems = seededOCR?.lineItems ?? []

        // Auto-select the best line item: first .product, or the most expensive item.
        let autoSelected: LineItem? = {
            let items = seededOCR?.lineItems ?? []
            guard !items.isEmpty else { return nil }
            // First product-classified item
            if let product = items.first(where: { $0.kind == .product }) {
                return product
            }
            // Most expensive record-worthy item
            if let expensive = items
                .filter({ $0.kind.isRecordWorthy })
                .max(by: { ($0.amount ?? 0) < ($1.amount ?? 0) }) {
                return expensive
            }
            // Fallback: most expensive item of any kind (except fee)
            return items
                .filter({ $0.kind != .fee })
                .max(by: { ($0.amount ?? 0) < ($1.amount ?? 0) })
        }()

        _selectedItemId = State(initialValue: autoSelected?.id)

        // Pre-fill from auto-selected item if available, otherwise from OCR suggestions
        let initialProductName = autoSelected?.name ?? seededOCR?.suggestedProductName ?? ""
        let initialAmount: String = {
            if let amount = autoSelected?.amount {
                return String(format: "%.2f", amount)
            } else if let amount = seededOCR?.suggestedAmount {
                return String(format: "%.2f", amount)
            }
            return ""
        }()

        _productName = State(initialValue: initialProductName)
        _merchantName = State(initialValue: seededOCR?.suggestedMerchantName ?? "")
        _notes = State(initialValue: seededOCR?.suggestedNotes ?? "")
        _purchaseDate = State(initialValue: seededOCR?.suggestedPurchaseDate ?? .now)
        _amountText = State(initialValue: initialAmount)
        _currency = State(initialValue: seededOCR?.suggestedCurrency ?? "SGD")
        _category = State(initialValue: seededOCR?.suggestedCategory ?? "")

        // If Foundation Models extracted a warranty duration, pre-fill the warranty toggle and date.
        // Also auto-enable warranty if any line item is classified as a warranty.
        let hasWarrantyItem = (seededOCR?.lineItems ?? []).contains(where: { $0.kind == .warranty })
        if let months = seededOCR?.suggestedWarrantyDurationMonths,
           let purchaseDate = seededOCR?.suggestedPurchaseDate,
           let expiryDate = Calendar.current.date(byAdding: .month, value: months, to: purchaseDate) {
            _includeWarranty = State(initialValue: true)
            _warrantyExpiryDate = State(initialValue: expiryDate)
        } else if hasWarrantyItem {
            _includeWarranty = State(initialValue: true)
        }
    }

    // MARK: - Confidence helpers

    /// Get the confidence for a specific field from the structured result.
    private func confidence(for keyPath: KeyPath<StructuredExtractionResult, ExtractedField<String>>) -> ExtractionConfidence? {
        guard let sr = structuredResult, sr[keyPath: keyPath].value != nil else { return nil }
        return sr[keyPath: keyPath].confidence
    }

    private var amountConfidence: ExtractionConfidence? {
        guard let sr = structuredResult, sr.amount.value != nil else { return nil }
        return sr.amount.confidence
    }

    private var dateConfidence: ExtractionConfidence? {
        guard let sr = structuredResult, sr.purchaseDate.value != nil else { return nil }
        return sr.purchaseDate.confidence
    }

    private var warrantyConfidence: ExtractionConfidence? {
        guard let sr = structuredResult, sr.warrantyDurationMonths.value != nil else { return nil }
        return sr.warrantyDurationMonths.confidence
    }

    var body: some View {
        Form {
            // Document kind + OCR text section
            if let seededOCR, !seededOCR.recognizedText.isEmpty {
                Section("Extracted text") {
                    // Document kind badge
                    if let kind = seededOCR.documentKind, kind != .unknown {
                        HStack(spacing: 6) {
                            Image(systemName: iconForDocumentKind(kind))
                                .font(.caption)
                            Text(kind.label)
                                .font(.caption.weight(.medium))
                            if let sr = structuredResult,
                               sr.documentKind.confidence.needsReview {
                                ExtractionBadgeView(confidence: sr.documentKind.confidence)
                            }
                        }
                        .foregroundStyle(.blue)
                        .padding(.bottom, 2)
                    }

                    Text(seededOCR.recognizedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)

                    if let source = seededOCR.extractionSource {
                        HStack(spacing: 6) {
                            Image(systemName: source == .foundationModel ? "cpu" : "text.magnifyingglass")
                                .font(.caption2)
                            Text(source == .foundationModel
                                ? "Extracted with Apple Intelligence"
                                : "Extracted with pattern matching")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                        // Show diagnostic detail when Foundation Models didn't run.
                        if let diag = seededOCR.structuredResult?.diagnostics,
                           !diag.foundationModelRan {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                if let reason = diag.foundationModelSkipReason {
                                    Text("AI unavailable: \(reason)")
                                        .font(.caption2)
                                } else {
                                    Text("AI extraction did not run on this document")
                                        .font(.caption2)
                                }
                            }
                            .foregroundStyle(.orange)
                        }

                        // Share extraction log button — available when structured result exists.
                        if seededOCR.structuredResult != nil {
                            Button {
                                showExtractionLogSheet = true
                            } label: {
                                Label("Share extraction log", systemImage: "square.and.arrow.up")
                                    .font(.caption2)
                            }
                            .padding(.top, 2)
                        }
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

            // Line item picker — shown when multiple items were extracted
            if !lineItems.isEmpty {
                Section("Items on this receipt") {
                    ForEach(lineItems) { item in
                        Button {
                            selectItem(item)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(item.kind.isRecordWorthy ? .body.bold() : .body)
                                    Text(item.kind.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let amount = item.amount {
                                    Text(String(format: "%.2f", amount))
                                        .font(.body.monospacedDigit())
                                }
                                if selectedItemId == item.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .tint(.primary)
                        .disabled(item.kind == .fee)
                    }
                }
            }

            Section("Details") {
                ExtractedTextField(
                    title: "Product name",
                    text: $productName,
                    confidence: confidence(for: \.productName)
                )
                ExtractedTextField(
                    title: "Store",
                    text: $merchantName,
                    confidence: confidence(for: \.merchantName)
                )
                HStack {
                    DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)
                    if let conf = dateConfidence, conf.needsReview {
                        ExtractionBadgeView(confidence: conf)
                    }
                }
            }

            Section("Amount") {
                HStack {
                    ExtractedTextField(
                        title: "Amount",
                        text: $amountText,
                        confidence: amountConfidence
                    )
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
                HStack {
                    Toggle("Add warranty expiry", isOn: $includeWarranty)
                    if let conf = warrantyConfidence, conf.needsReview {
                        ExtractionBadgeView(confidence: conf)
                    }
                }
                if includeWarranty {
                    DatePicker("Warranty expires", selection: $warrantyExpiryDate, displayedComponents: .date)
                }
            }

            Section("Organization") {
                ExtractedTextField(
                    title: "Category (e.g. Electronics, Kitchen)",
                    text: $category,
                    confidence: confidence(for: \.category)
                )
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
        .sheet(isPresented: $showExtractionLogSheet) {
            if let logText = generateExtractionLog() {
                ShareSheetView(activityItems: [logText])
            }
        }
        .task {
            guard learningContext == nil, let structuredResult else { return }
            let service = MerchantLearningService(modelContext: modelContext)
            learningContext = service.learningContext(for: structuredResult)
            applyLearningContextIfHelpful()
        }
    }

    private func applyLearningContextIfHelpful() {
        guard let learningContext else { return }

        if category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let suggestedCategory = learningContext.categorySuggestion,
           !suggestedCategory.isEmpty {
            category = suggestedCategory
        }

        if currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currency == "SGD",
           let suggestedCurrency = learningContext.currencySuggestion,
           !suggestedCurrency.isEmpty,
           seededOCR?.suggestedCurrency == nil {
            currency = suggestedCurrency
        }

        if !includeWarranty,
           let months = learningContext.warrantySuggestionMonths,
           months > 0,
           let expiryDate = Calendar.current.date(byAdding: .month, value: months, to: purchaseDate) {
            includeWarranty = true
            warrantyExpiryDate = expiryDate
        }
    }

    // MARK: - Item selection

    /// Called when the user taps a line item to select it as the main record item.
    private func selectItem(_ item: LineItem) {
        selectedItemId = item.id
        productName = item.name
        if let amount = item.amount {
            amountText = String(format: "%.2f", amount)
        }
        // Auto-toggle warranty if any line item is a warranty
        let hasWarrantyLineItem = lineItems.contains(where: { $0.kind == .warranty })
        if hasWarrantyLineItem && !includeWarranty {
            includeWarranty = true
        }
    }

    // MARK: - Document kind icon

    private func iconForDocumentKind(_ kind: DocumentKind) -> String {
        switch kind {
        case .receipt: "receipt"
        case .invoice: "doc.text"
        case .warrantyCard: "shield.lefthalf.filled"
        case .orderConfirmation: "checkmark.circle"
        case .packingSlip: "shippingbox"
        case .supportDocument: "wrench.and.screwdriver"
        case .manual: "book"
        case .unknown: "questionmark.folder"
        }
    }

    // MARK: - Extraction log

    private func generateExtractionLog() -> String? {
        guard let ocr = seededOCR, let sr = ocr.structuredResult else { return nil }
        let diag = sr.diagnostics

        var lines: [String] = []
        lines.append("📋 PaperTrail Extraction Log")
        lines.append("═══════════════════════════════")
        lines.append("")

        // OCR text preview
        let ocrPreview = String(ocr.recognizedText.prefix(1500))
        lines.append("📝 OCR Text (\(ocr.recognizedText.count) chars):")
        lines.append(ocrPreview)
        if ocr.recognizedText.count > 1500 {
            lines.append("… (truncated)")
        }
        lines.append("")

        // Document kind
        if let kind = ocr.documentKind {
            let kindConf = sr.documentKind.confidence.rawValue
            lines.append("📄 Document: \(kind.label) [\(kindConf)]")
        }
        lines.append("")

        // Foundation Models status
        lines.append("🤖 Foundation Models:")
        if let diag {
            lines.append("  Available: \(diag.foundationModelAvailable ? "yes" : "no")")
            lines.append("  Ran: \(diag.foundationModelRan ? "yes" : "no")")
            if let reason = diag.foundationModelSkipReason {
                lines.append("  Skip reason: \(reason)")
            }
            lines.append("  FM fields: \(diag.foundationModelFieldCount)")
            lines.append("  Heuristic fields: \(diag.heuristicFieldCount)")
        } else {
            lines.append("  No diagnostics available")
        }
        lines.append("")

        // Fields
        lines.append("📊 Extracted Fields:")

        func fieldLine<T>(_ name: String, _ field: ExtractedField<T>) -> String {
            if let v = field.value {
                return "  \(name): \(v) [\(field.confidence.rawValue)]"
            }
            return "  \(name): — [none]"
        }

        lines.append(fieldLine("Product", sr.productName))
        lines.append(fieldLine("Merchant", sr.merchantName))
        if let date = sr.purchaseDate.value {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            lines.append("  Date: \(fmt.string(from: date)) [\(sr.purchaseDate.confidence.rawValue)]")
        } else {
            lines.append("  Date: — [none]")
        }
        lines.append(fieldLine("Amount", sr.amount))
        lines.append(fieldLine("Currency", sr.currency))
        lines.append(fieldLine("Category", sr.category))
        lines.append(fieldLine("Warranty (months)", sr.warrantyDurationMonths))
        lines.append("")

        // Line items
        if !sr.lineItems.isEmpty {
            lines.append("")
            lines.append("🛒 Line Items (\(sr.lineItems.count)):")
            for item in sr.lineItems {
                let amountStr = item.amount.map { String(format: "%.2f", $0) } ?? "—"
                lines.append("  [\(item.kind.label)] \(item.name): \(amountStr)")
            }
        }

        // Source
        lines.append("🔧 Source: \(sr.source.rawValue)")

        // Rejected fields
        if let diag, !diag.rejectedFields.isEmpty {
            lines.append("")
            lines.append("⚠️ Rejected: \(diag.rejectedFields.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Save

    private func saveRecord() {
        let parsedAmount = Double(amountText.replacingOccurrences(of: ",", with: ""))
        let parsedTags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        // Log corrections before saving — compare extraction vs user's final values.
        let finalWarrantyMonths: Int? = {
            guard includeWarranty,
                  let sr = structuredResult,
                  let originalMonths = sr.warrantyDurationMonths.value else { return nil }
            // Reverse-calculate months from the user's chosen dates to compare.
            let months = Calendar.current.dateComponents([.month], from: purchaseDate, to: warrantyExpiryDate).month
            return months != originalMonths ? months : originalMonths
        }()

        CorrectionLogger.onLearningFeedback = { payload in
            Task { @MainActor in
                let service = MerchantLearningService(modelContext: modelContext)
                service.captureFeedback(payload)
            }
        }

        CorrectionLogger.logCorrections(
            structured: structuredResult,
            documentKind: seededOCR?.documentKind,
            finalProductName: productName,
            finalMerchantName: merchantName,
            finalPurchaseDate: purchaseDate,
            finalAmount: parsedAmount,
            finalCurrency: currency,
            finalCategory: category,
            finalWarrantyMonths: finalWarrantyMonths
        )

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
