import SwiftUI
import SwiftData
import UIKit

struct DraftRecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @State private var learningContext: MerchantLearningContext?

    let seedType: AttachmentType
    let seededAttachments: [Attachment]
    let seededOCR: OCRExtractionResult?
    /// True when `seededAttachments` is a single product photo from the add
    /// sheet's "Photograph the thing" (v3 §3), not proof of purchase — on
    /// save, that attachment is filed as `productImageAttachmentID` rather
    /// than a regular document attachment. Defaults false for every other
    /// entry point (scan, barcode, voice, Mail/Files import).
    let seedsProductImage: Bool

    /// The structured extraction result preserved for confidence badges and correction logging.
    private let structuredResult: StructuredExtractionResult?

    @State private var productName: String
    @State private var merchantName: String
    @State private var notes: String
    @State private var purchaseDate: Date
    @State private var includeWarranty = false
    @State private var warrantyExpiryDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var returnWindowDays: Int?
    @State private var amountText: String
    @State private var currency: String
    @State private var category: String = ""
    @State private var room: String = ""
    @State private var tagsText: String = ""
    /// Suggested serial number from the passive barcode sweep (see
    /// `BarcodeDetectionService`). Pre-filled only when a candidate was
    /// found; the user can edit/clear it like any other field.
    @State private var serialNumber: String = ""

    /// Existing records, used only to surface previously-used rooms in the picker.
    @Query private var allRecords: [PurchaseRecord]
    @State private var showExtractionLogSheet = false
    /// The scanned image presented full-screen when the review thumbnail is tapped.
    @State private var selectedImageFilename: SelectedFilename?
    @State private var showRawText = false

    /// Additional proof pages scanned via "Add another page" before saving.
    @State private var extraAttachments: [Attachment] = []
    @State private var showAddScanner = false
    private let scanningService = ScanningService()

    /// Line items extracted from the document, for user selection.
    private let lineItems: [LineItem]
    /// The currently selected line item ID (user picks the main item for the record).
    /// Line items the user wants to save. Each becomes its own record; the first
    /// (in display order) is the "primary" whose fields are editable in the form.
    @State private var selectedItemIds: Set<UUID> = []
    /// Per-item inline edits for the non-primary selected items (name / price text),
    /// keyed by line-item id. Absent keys fall back to the item's extracted values.
    @State private var itemNameEdits: [UUID: String] = [:]
    @State private var itemPriceEdits: [UUID: String] = [:]

    init(seedType: AttachmentType, seededAttachments: [Attachment] = [], seededOCR: OCRExtractionResult? = nil, seedsProductImage: Bool = false) {
        self.seedType = seedType
        self.seededAttachments = seededAttachments
        self.seededOCR = seededOCR
        self.seedsProductImage = seedsProductImage
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

        _selectedItemIds = State(initialValue: autoSelected.map { Set([$0.id]) } ?? [])

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
        _currency = State(initialValue: seededOCR?.suggestedCurrency ?? PTCurrency.deviceDefault)
        _category = State(initialValue: seededOCR?.suggestedCategory ?? "")
        _room = State(initialValue: "")
        _serialNumber = State(initialValue: seededOCR?.serialCandidate?.payload ?? "")

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

    /// Confidence styling for the barcode-suggested serial number. A
    /// `.serial`-shaped payload reads as "Auto" (barcode decoding is exact,
    /// unlike OCR/FM guesses); a `.productCode` payload is flagged for
    /// review since it's a lower-confidence fallback, not a true serial.
    private var serialConfidence: ExtractionConfidence? {
        switch seededOCR?.serialCandidate?.kind {
        case .serial: .high
        case .productCode: .medium
        case nil: nil
        }
    }

    private var dateConfidence: ExtractionConfidence? {
        guard let sr = structuredResult, sr.purchaseDate.value != nil else { return nil }
        return sr.purchaseDate.confidence
    }

    private var warrantyConfidence: ExtractionConfidence? {
        guard let sr = structuredResult, sr.warrantyDurationMonths.value != nil else { return nil }
        return sr.warrantyDurationMonths.confidence
    }

    private var detectedFieldCount: Int {
        [productName, merchantName, amountText, category].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            + (seededOCR?.suggestedPurchaseDate != nil ? 1 : 0)
            + (includeWarranty ? 1 : 0)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                reviewHeader

                if !lineItems.isEmpty {
                    lineItemCard
                }

                fieldsCard

                serialSuggestionCard

                additionalItemCards

                organizationCard

                if let seededOCR, !seededOCR.recognizedText.isEmpty {
                    extractedTextCard(seededOCR)
                }

                VStack(spacing: 10) {
                    Button { saveRecord() } label: {
                        Text("Save to Library")
                    }
                    .buttonStyle(PTGoldButtonStyle())
                    .disabled(productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

                    Button { showAddScanner = true } label: {
                        Label(extraAttachments.isEmpty ? "Add another page" : "Add another page (\(extraAttachments.count) added)", systemImage: "plus")
                    }
                    .buttonStyle(PTOutlineButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.bottom, 80)
        }
        .ptScreen()
        .navigationBarBackButtonHidden()
        .ptKeyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Retake")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
        .sheet(isPresented: $showExtractionLogSheet) {
            if let logText = generateExtractionLog() {
                ShareSheetView(activityItems: [logText])
            }
        }
        .fullScreenCover(isPresented: $showAddScanner) {
            DocumentScannerView(
                onScanComplete: { images in
                    showAddScanner = false
                    Task {
                        let learned = MerchantLearningService(modelContext: modelContext).learnedMerchantNames()
                        let result = await scanningService.process(images: images, type: seedType, learnedMerchants: learned)
                        extraAttachments.append(contentsOf: result.attachments)
                    }
                },
                onCancel: { showAddScanner = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $selectedImageFilename) { selected in
            ImageViewerView(filename: selected.value, attachmentID: selected.attachmentID)
        }
        .task {
            guard learningContext == nil, let structuredResult else { return }
            let service = MerchantLearningService(modelContext: modelContext)
            learningContext = service.learningContext(for: structuredResult)
            applyLearningContextIfHelpful()
        }
    }

    // MARK: Review header

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review")
                .font(PTFont.serif(34, weight: 600))
                .foregroundStyle(PT.txt)
                .padding(.top, 8)

            HStack(spacing: 10) {
                if let attachment = seededAttachments.first, let image = attachment.image {
                    Button {
                        selectedImageFilename = SelectedFilename(attachment.localFilename, attachmentID: attachment.id)
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 54, height: 72)
                            .clipShape(DogEarShape(radius: 8, ear: 12))
                            .overlay(DogEarShape(radius: 8, ear: 12).stroke(PT.hair, lineWidth: 1))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(.black.opacity(0.45), in: Circle())
                                    .padding(4)
                            }
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 6) {
                    let merchant = merchantName.isEmpty ? (seededOCR?.suggestedMerchantName ?? (seedsProductImage ? "product photo" : "receipt")) : merchantName
                    Chip(symbol: "checkmark.circle", text: seedsProductImage ? "Photographed · \(merchant)" : "Scanned · \(merchant)", tone: PT.sage)
                    Text("\(detectedFieldCount) fields detected")
                        .font(PTFont.mono(10))
                        .foregroundStyle(PT.txt3)
                }
                Spacer()
            }
        }
    }

    // MARK: Fields card

    private var fieldsCard: some View {
        VStack(spacing: 0) {
            PTReviewField(title: "Product", text: $productName, confidence: confidence(for: \.productName))
            paperDivider
            PTReviewField(title: "Merchant", text: $merchantName, confidence: confidence(for: \.merchantName))
            paperDivider
            PTReviewDateRow(title: "Purchase date", date: $purchaseDate, confidence: dateConfidence)
            paperDivider
            HStack(alignment: .bottom, spacing: 12) {
                PTReviewField(title: "Price", text: $amountText, keyboard: .decimalPad, mono: true, confidence: amountConfidence)
                Picker("Currency", selection: $currency) {
                    Text("SGD").tag("SGD"); Text("USD").tag("USD"); Text("MYR").tag("MYR")
                    Text("EUR").tag("EUR"); Text("GBP").tag("GBP"); Text("JPY").tag("JPY")
                }
                .pickerStyle(.menu)
                .tint(PT.onPaper2)
                .padding(.bottom, 8)
            }
            paperDivider
            warrantyRow
            paperDivider
            returnWindowRow
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: true)
    }

    /// Suggested-serial card from the passive barcode sweep — only rendered
    /// when a candidate was found on a scanned page. Editable/clearable like
    /// any other review field; clearing it saves the record with no serial,
    /// same as if no barcode had been found.
    @ViewBuilder
    private var serialSuggestionCard: some View {
        if let candidate = seededOCR?.serialCandidate {
            VStack(spacing: 0) {
                PTReviewField(title: candidate.kind.label, text: $serialNumber, mono: true, confidence: serialConfidence)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard(goldFold: false)
        }
    }

    /// One editable card per *additional* selected item (the primary is edited in
    /// `fieldsCard`). Each becomes its own record, sharing the merchant/date/room/
    /// currency/warranty above; per-item category is editable later in Edit.
    @ViewBuilder
    private var additionalItemCards: some View {
        ForEach(Array(recordWorthySelectedItems.dropFirst())) { item in
            VStack(spacing: 0) {
                HStack {
                    SectionLabel(text: "Additional item", tone: PT.gold)
                    Spacer()
                    Button { toggleItem(item) } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(PT.txt3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)
                PTReviewField(title: "Product", text: itemNameBinding(item), confidence: nil)
                paperDivider
                PTReviewField(title: "Price", text: itemPriceBinding(item), keyboard: .decimalPad, mono: true, confidence: nil)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard(goldFold: false)
        }
    }

    private var warrantyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $includeWarranty) {
                    Text("Warranty")
                        .ptMonoLabel(9, tracking: 1.4)
                        .foregroundStyle(PT.onPaper3)
                }
                .tint(PT.sage)
                if let conf = warrantyConfidence, conf.needsReview {
                    ConfidenceTag(confidence: conf)
                }
            }
            if includeWarranty {
                DatePicker("", selection: $warrantyExpiryDate, displayedComponents: .date)
                    .labelsHidden()
                    .tint(PT.goldDeep)
            }
        }
        .padding(.vertical, 12)
    }

    private var returnWindowRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Return window")
                .ptMonoLabel(9, tracking: 1.4)
                .foregroundStyle(PT.onPaper3)
            ReturnWindowPicker(returnWindowDays: $returnWindowDays)
                .font(PTFont.serif(17, weight: 500))
                .tint(PT.goldDeep)
        }
        .padding(.vertical, 12)
    }

    // MARK: Organization

    private var organizationCard: some View {
        VStack(spacing: 0) {
            PTReviewField(title: "Category", text: $category, confidence: confidence(for: \.category))
            paperDivider
            roomField
            paperDivider
            PTReviewField(title: "Tags (comma separated)", text: $tagsText, confidence: nil)
            paperDivider
            PTReviewField(title: "Notes", text: $notes, confidence: nil)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: false)
    }

    /// Room selector styled to match the cream filing-card fields.
    private var roomField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Room")
                .ptMonoLabel(9, tracking: 1.4)
                .foregroundStyle(PT.onPaper3)
            RoomPicker(room: $room, suggestions: RoomOptions.suggestions(existing: allRecords.compactMap(\.room)))
                .font(PTFont.serif(17, weight: 500))
                .tint(PT.goldDeep)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    // MARK: Line item picker

    /// Items selected to save, in display order; the first is the editable primary.
    private var selectedItems: [LineItem] {
        lineItems.filter { selectedItemIds.contains($0.id) }
    }

    /// Selected items that become records. The first (primary) is edited in the
    /// main form card; the rest each get their own card below.
    private var recordWorthySelectedItems: [LineItem] {
        selectedItems.filter { $0.kind.isRecordWorthy }
    }

    private func defaultPriceText(_ item: LineItem) -> String {
        item.amount.map { String(format: "%.2f", $0) } ?? ""
    }

    private func itemNameBinding(_ item: LineItem) -> Binding<String> {
        Binding(get: { itemNameEdits[item.id] ?? item.name },
                set: { itemNameEdits[item.id] = $0 })
    }

    private func itemPriceBinding(_ item: LineItem) -> Binding<String> {
        Binding(get: { itemPriceEdits[item.id] ?? defaultPriceText(item) },
                set: { itemPriceEdits[item.id] = $0 })
    }

    /// Final name/price for a non-primary item, applying any inline edits.
    private func editedName(for item: LineItem) -> String {
        let edited = (itemNameEdits[item.id] ?? item.name).trimmingCharacters(in: .whitespacesAndNewlines)
        return edited.isEmpty ? item.name : edited
    }

    private func editedAmount(for item: LineItem) -> Double? {
        guard let text = itemPriceEdits[item.id] else { return item.amount }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return Self.parseAmount(trimmed) ?? item.amount
    }

    /// Parse a user-typed amount, honouring the device locale's decimal separator
    /// (so "1.299,00" on a comma-decimal keyboard isn't silently dropped) before
    /// falling back to plain "1,299.00" grouping.
    static func parseAmount(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        if let n = formatter.number(from: trimmed) { return n.doubleValue }
        return Double(trimmed.replacingOccurrences(of: ",", with: ""))
    }

    private var lineItemCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Items on this receipt", tone: PT.txt3)
            VStack(spacing: 0) {
                ForEach(lineItems) { item in
                    let isSelected = selectedItemIds.contains(item.id)
                    let isPrimary = recordWorthySelectedItems.first?.id == item.id
                    Button { toggleItem(item) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16))
                                .foregroundStyle(isSelected ? PT.gold : PT.txt3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(item.kind.isRecordWorthy ? PTFont.serif(15, weight: 600) : PTFont.serif(15, weight: 500))
                                    .foregroundStyle(PT.txt)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Text(item.kind.label)
                                        .font(PTFont.mono(9))
                                        .foregroundStyle(PT.txt3)
                                    if isPrimary && recordWorthySelectedItems.count > 1 {
                                        Text("EDITING")
                                            .font(PTFont.mono(8))
                                            .foregroundStyle(PT.gold)
                                    }
                                }
                            }
                            Spacer(minLength: 8)
                            if let amount = item.amount {
                                Text(String(format: "%.2f", amount))
                                    .font(PTFont.mono(12, medium: true))
                                    .foregroundStyle(PT.txt2)
                            }
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(item.kind == .fee)
                    .opacity(item.kind == .fee ? 0.5 : 1)

                    if item.id != lineItems.last?.id {
                        Rectangle().fill(PT.hair).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Color(hex: 0xE7DCC4, alpha: 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PT.hair, lineWidth: 1))

            if recordWorthySelectedItems.count > 1 {
                Text("Saving \(recordWorthySelectedItems.count) items as separate records — the “Editing” item uses the card below; each other selected item gets its own card to edit.")
                    .font(PTFont.mono(9))
                    .foregroundStyle(PT.txt3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Extracted text (diagnostics)

    @ViewBuilder
    private func extractedTextCard(_ ocr: OCRExtractionResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation { showRawText.toggle() } } label: {
                HStack {
                    SectionLabel(text: "Extracted text", tone: PT.txt3)
                    if let kind = ocr.documentKind, kind != .unknown {
                        Text(kind.label)
                            .font(PTFont.mono(9))
                            .foregroundStyle(PT.gold)
                    }
                    Spacer()
                    Image(systemName: showRawText ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PT.txt3)
                }
            }
            .buttonStyle(.plain)

            if showRawText {
                Text(ocr.recognizedText)
                    .font(PTFont.mono(10))
                    .foregroundStyle(PT.txt2)
                    .lineLimit(12)
                    .textSelection(.enabled)
            }

            if let source = ocr.extractionSource {
                HStack(spacing: 6) {
                    Image(systemName: source == .foundationModel ? "cpu" : "text.magnifyingglass")
                        .font(.system(size: 10))
                    Text(source == .foundationModel ? "Extracted with Apple Intelligence" : "Extracted with pattern matching")
                        .font(PTFont.mono(9.5))
                }
                .foregroundStyle(PT.txt3)

                if let diag = ocr.structuredResult?.diagnostics, !diag.foundationModelRan {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle").font(.system(size: 10))
                        Text(diag.foundationModelSkipReason.map { "AI unavailable: \($0)" } ?? "AI extraction did not run on this document")
                            .font(PTFont.mono(9.5))
                    }
                    .foregroundStyle(PT.amber)
                }

                if ocr.structuredResult != nil {
                    Button { showExtractionLogSheet = true } label: {
                        Label("Share extraction log", systemImage: "square.and.arrow.up")
                            .font(PTFont.mono(9.5))
                            .foregroundStyle(PT.txt3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xE7DCC4, alpha: 0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }

    private var paperDivider: some View {
        Rectangle().fill(PT.onPaperHair).frame(height: 1)
    }

    private func applyLearningContextIfHelpful() {
        guard let learningContext else { return }

        if category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Prefer the merchant's learned category; fall back to item-level
            // product → category memory ("AirPods" → Electronics) for products
            // bought somewhere new.
            if let suggestedCategory = learningContext.categorySuggestion, !suggestedCategory.isEmpty {
                category = suggestedCategory
            } else if !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let service = MerchantLearningService(modelContext: modelContext)
                if let learned = service.productCategorySuggestion(for: productName) {
                    category = learned
                }
            }
        }

        if currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currency == PTCurrency.deviceDefault,
           let suggestedCurrency = learningContext.currencySuggestion,
           !suggestedCurrency.isEmpty,
           seededOCR?.suggestedCurrency == nil {
            currency = suggestedCurrency
        }

        // Warranty auto-apply changes the saved expiry date, so only do it when
        // the profile is trustworthy enough (avoids one stray correction flipping
        // warranty on for every future scan from that merchant).
        if !includeWarranty,
           learningContext.confidence >= 0.3,
           let months = learningContext.warrantySuggestionMonths,
           months > 0,
           let expiryDate = Calendar.current.date(byAdding: .month, value: months, to: purchaseDate) {
            includeWarranty = true
            warrantyExpiryDate = expiryDate
        }
    }

    // MARK: - Item selection

    /// Called when the user taps a line item to select it as the main record item.
    private func toggleItem(_ item: LineItem) {
        let previousPrimary = recordWorthySelectedItems.first
        if selectedItemIds.contains(item.id) {
            selectedItemIds.remove(item.id)
        } else {
            selectedItemIds.insert(item.id)
        }
        // Rebind the main form to the new primary without clobbering values the
        // user hand-edited — the rule lives in PrimaryItemBinding so it's testable.
        let bound = PrimaryItemBinding.rebound(
            previousPrimary: previousPrimary,
            newPrimary: recordWorthySelectedItems.first,
            current: .init(productName: productName, amountText: amountText)
        )
        productName = bound.productName
        amountText = bound.amountText
        // Auto-toggle warranty if any selected line item is a warranty.
        if selectedItems.contains(where: { $0.kind == .warranty }) && !includeWarranty {
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

        // Build one record per selected line item (each tracked separately, with
        // its own warranty/category/amount). The primary item uses the edited
        // form fields; additional items use their receipt values. With 0–1
        // record-worthy items selected, this is exactly one record from the form.
        // Only the primary record (the one edited in `fieldsCard`) gets the
        // barcode-suggested serial — additional selected items are separate
        // physical products that would need their own barcode.
        let trimmedSerial = serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSerialNumber: String? = trimmedSerial.isEmpty ? nil : trimmedSerial

        func makeRecord(productName: String, amount: Double?, category: String?, serialNumber: String? = nil) -> PurchaseRecord {
            PurchaseRecord(
                productName: productName,
                merchantName: merchantName.isEmpty ? nil : merchantName,
                purchaseDate: purchaseDate,
                warrantyExpiryDate: includeWarranty ? warrantyExpiryDate : nil,
                notes: notes.isEmpty ? nil : notes,
                amount: amount,
                currency: currency,
                category: (category?.isEmpty == false) ? category : nil,
                room: room.isEmpty ? nil : room,
                tags: parsedTags,
                returnWindowDays: returnWindowDays,
                serialNumber: serialNumber
            )
        }

        let recordWorthySelected = selectedItems.filter { $0.kind.isRecordWorthy }
        var records: [PurchaseRecord] = []
        if recordWorthySelected.count >= 2 {
            for (index, item) in recordWorthySelected.enumerated() {
                records.append(index == 0
                    ? makeRecord(productName: productName, amount: parsedAmount, category: category, serialNumber: finalSerialNumber)
                    : makeRecord(productName: editedName(for: item), amount: editedAmount(for: item), category: item.category ?? category))
            }
        } else {
            records.append(makeRecord(productName: productName, amount: parsedAmount, category: category, serialNumber: finalSerialNumber))
        }

        for record in records {
            modelContext.insert(record)
        }

        // Attachments: link the originals to the primary record; for any extra
        // records, duplicate the metadata pointing at the same on-disk image files
        // so every record shows the receipt.
        let allAttachments = seededAttachments + extraAttachments
        var attachmentsByRecord: [UUID: [Attachment]] = [:]
        if let primary = records.first {
            for attachment in allAttachments {
                attachment.recordID = primary.id
                modelContext.insert(attachment)
            }
            attachmentsByRecord[primary.id] = allAttachments
            // "Photograph the thing" (v3 §3): the single seeded attachment is
            // a product photo, not proof of purchase — file it as the
            // product image so LibraryView's "ADD PROOF" pill (no document
            // attachments yet) can key off it.
            if seedsProductImage, let productPhoto = seededAttachments.first {
                primary.productImageAttachmentID = productPhoto.id
            }
            for record in records.dropFirst() {
                var dups: [Attachment] = []
                for attachment in allAttachments {
                    let dup = Attachment(type: attachment.type, localFilename: attachment.localFilename, ocrText: attachment.ocrText)
                    dup.recordID = record.id
                    modelContext.insert(dup)
                    dups.append(dup)
                }
                attachmentsByRecord[record.id] = dups
            }
        }

        // Index every new record for on-device Spotlight search.
        for record in records {
            SpotlightIndexer.index(record, attachments: attachmentsByRecord[record.id] ?? [])
        }

        // Schedule reminders per the user's preferences (§1-B, §6). Use the
        // scheduler's own return value (0 or 1 requests submitted) to decide
        // whether to stamp "scheduled" — stamping unconditionally lies about
        // records with no expiry/deadline to anchor to, or where the lead
        // time would already fire in the past. `rescheduleAll` re-arms
        // anything left unstamped once the user later grants permission.
        let reminderPrefs = ReminderSettings.shared
        if includeWarranty, reminderPrefs.warrantyRemindersEnabled {
            for record in records {
                let count = NotificationManager.shared.scheduleWarrantyReminders(for: record, leadDays: reminderPrefs.warrantyLeadTime.days)
                record.warrantyNotificationScheduled = count > 0
            }
        }
        if returnWindowDays != nil, reminderPrefs.returnWindowRemindersEnabled {
            for record in records {
                let count = NotificationManager.shared.scheduleReturnWindowReminder(for: record)
                record.returnWindowNotificationScheduled = count > 0
            }
        }

        // Upload attachment images to CloudKit in the background
        let attachmentsToUpload = allAttachments.map {
            AttachmentSyncInfo(id: $0.id, localFilename: $0.localFilename)
        }
        Task {
            for info in attachmentsToUpload {
                await cloudImageSync.upload(attachmentID: info.id, localFilename: info.localFilename)
            }
        }

        // Delight moment: a successful scan→save, never on an error path.
        ReviewPrompter.shared.recordsSaved(records.count)

        // Notification soft-ask (N1): only ever triggers on the user's very
        // first successful save, using the real just-saved item's name and
        // warranty date in the sample notification.
        if let primary = records.first {
            SoftAskCoordinator.shared.recordSaved(
                count: records.count,
                itemName: primary.productName,
                warrantyExpiryDate: primary.warrantyExpiryDate
            )
            // v3 animPassV3 §9 "Receipt prints on save": hand LibraryView the
            // just-saved record's id so it can give that one card its
            // translateY-from-top entrance. No-op (never set) when the flag
            // is off, matching v2 exactly.
            if AnimPass.isOn {
                AppRouter.shared.lastSavedRecordID = primary.id
            }
        }

        dismiss()
    }
}

// MARK: - Themed review field components

/// Confidence affordance: sage "Auto" for high-confidence, amber "Check this" otherwise.
struct ConfidenceTag: View {
    let confidence: ExtractionConfidence?

    var body: some View {
        if let confidence {
            if confidence == .high {
                tag(dot: PT.sage, text: "Auto", tone: PT.sageDeep)
            } else if confidence.needsReview {
                tag(dot: PT.amber, text: "Check this", tone: Color(hex: 0x9A6B1F))
            }
        }
    }

    private func tag(dot: Color, text: String, tone: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(dot).frame(width: 5, height: 5)
            Text(text)
                .font(PTFont.mono(9, medium: true))
                .tracking(0.6)
                .textCase(.uppercase)
        }
        .foregroundStyle(tone)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(dot.opacity(0.14), in: Capsule())
    }
}

/// A labelled editable field rendered on a cream filing card, with a confidence tag.
struct PTReviewField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var mono: Bool = false
    let confidence: ExtractionConfidence?

    private var needsReview: Bool { confidence?.needsReview ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .ptMonoLabel(9, tracking: 1.4)
                    .foregroundStyle(PT.onPaper3)
                Spacer()
                ConfidenceTag(confidence: confidence)
            }
            TextField("", text: $text, prompt: Text("—").foregroundStyle(PT.onPaper3))
                .font(mono ? PTFont.mono(15, medium: true) : PTFont.serif(17, weight: 500))
                .foregroundStyle(needsReview ? Color(hex: 0x9A6B1F) : PT.onPaper)
                .tint(PT.goldDeep)
                .keyboardType(keyboard)
        }
        .padding(.vertical, 12)
    }
}

/// A labelled date row on a cream filing card.
struct PTReviewDateRow: View {
    let title: String
    @Binding var date: Date
    let confidence: ExtractionConfidence?

    var body: some View {
        HStack {
            Text(title)
                .ptMonoLabel(9, tracking: 1.4)
                .foregroundStyle(PT.onPaper3)
            if let confidence, confidence.needsReview {
                ConfidenceTag(confidence: confidence)
            }
            Spacer()
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .tint(PT.goldDeep)
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    NavigationStack {
        DraftRecordView(seedType: .receipt)
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
    .environmentObject(CloudImageSyncManager.shared)
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}

/// Pure decision for rebinding the main draft form to a new primary line item
/// without clobbering values the user hand-edited. Extracted from
/// `DraftRecordView.toggleItem` so the rule is unit-testable without SwiftUI state.
enum PrimaryItemBinding {
    struct Fields: Equatable {
        var productName: String
        var amountText: String
    }

    /// The field values after the primary selection changes. A field is
    /// overwritten only when it is empty or still equal to the previous primary's
    /// value (i.e. the user hasn't typed over it); otherwise the edit is kept.
    static func rebound(previousPrimary: LineItem?, newPrimary: LineItem?, current: Fields) -> Fields {
        guard let newPrimary, newPrimary.id != previousPrimary?.id else { return current }
        let prevName = previousPrimary?.name ?? ""
        let prevAmount = previousPrimary.flatMap(Self.amountText) ?? ""
        var result = current
        if current.productName.isEmpty || current.productName == prevName {
            result.productName = newPrimary.name
        }
        if current.amountText.isEmpty || current.amountText == prevAmount {
            result.amountText = Self.amountText(newPrimary) ?? ""
        }
        return result
    }

    /// The 2-decimal text form of a line item's amount, or nil when it has none.
    nonisolated static func amountText(_ item: LineItem) -> String? {
        item.amount.map { String(format: "%.2f", $0) }
    }
}
