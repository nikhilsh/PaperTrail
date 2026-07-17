import Foundation
import OSLog
import Sentry
import UIKit

/// Orchestrates field extraction from OCR text.
///
/// Strategy:
/// 1. Try Apple Foundation Models (on-device LLM) for structured extraction.
/// 2. If the model is unavailable or returns insufficient fields, fall back to heuristics.
/// 3. Merge results: prefer Foundation Model values where available, fill gaps with heuristics.
///
/// This design means the app works on every iOS 26 device — even those without Apple Intelligence
/// (e.g. base-model iPhones, or regions where it isn't enabled yet) — because the heuristic
/// fallback always runs.
///
/// Key principle: **prefer blank over bad**. When only heuristics are available, high-value
/// fields (product, merchant, date) are treated with extra skepticism. A blank field that
/// the user fills in is better than confidently wrong autofill.
struct ExtractionPipeline: Sendable {

    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "extraction.pipeline")

    private let foundationModelService: FieldExtractionService
    private let heuristicService: FieldExtractionService

    init(
        foundationModelService: FieldExtractionService = FoundationModelExtractionService(),
        heuristicService: FieldExtractionService = HeuristicExtractionService()
    ) {
        self.foundationModelService = foundationModelService
        self.heuristicService = heuristicService
    }

    /// Extract structured fields from an OCR *document* (text + optional structure).
    ///
    /// Runs the text-based extractors, then overlays structural signals from
    /// iOS 26's document recognizer: a structurally-read grand total beats the
    /// `pickLargerAmount` guess, and table-derived line items fill in when the
    /// extractors found none.
    func extract(from document: OCRDocument, image: UIImage? = nil, learningContext: MerchantLearningContext? = nil) async -> StructuredExtractionResult {
        var result = await extract(from: document.text, image: image, learningContext: learningContext)

        ExtractionMetrics.recordPipelineOutcome(
            source: result.source,
            usedStructuredOCR: document.structure != nil,
            foundationModelAvailable: result.diagnostics?.foundationModelAvailable ?? false,
            fmFieldCount: result.diagnostics?.foundationModelFieldCount ?? 0,
            heuristicFieldCount: result.diagnostics?.heuristicFieldCount ?? 0,
            hadStructuralTotal: document.structure?.hasStructuralTotal ?? false,
            lineItemCount: result.lineItems.count,
            structuredTableCount: document.structure?.tables.count ?? 0,
            structuredTableLineItemCount: document.structure?.tableLineItems.count ?? 0
        )

        if let structure = document.structure {
            result = applyStructure(structure, to: result)
        }

        // Last-resort, on-device category suggestion for products neither the
        // model nor the learning loop categorized.
        result = applyCategoryFallback(to: result)

        // Drop hallucinated prices: the model sometimes invents plausible-looking
        // per-item amounts that aren't on the receipt. Keep an amount only if its
        // digits actually appear in the OCR text — prefer blank over a made-up number.
        result = groundAmounts(result, text: document.text)

        // Final per-item price fill from the transcript itself. Vision's table grid
        // is often partial (it may capture item *names* but only some price cells),
        // so for any item still missing a price, find its line in the OCR text and
        // read the trailing money token. This is the catch-all that makes secondary
        // item prices auto-fill even when neither the model nor the table had them.
        result.lineItems = Self.overlayTextPrices(result.lineItems, text: document.text)

        // Sanity-filter the line items so the picker shows real products, not the
        // OCR noise that the column-major document transcript scatters between them
        // (bare model numbers, warranty/promo SKUs, free-gift lines, summary labels).
        result.lineItems = result.lineItems.filter { Self.isPlausibleProduct($0.name) }

        // Column-aware price fill for COLUMN-MAJOR transcripts (the follow-up the
        // build-14 diagnosis called for): when the recognizer serializes a table
        // column-by-column, a description and its price never share a line, so
        // the same-line overlay above fills nothing. But such receipts often carry
        // a repeated per-row cell (e.g. an "LCN" code) alternating 1:1 with the
        // unit-price column — a row anchor that recovers each row's price in
        // order. Runs after the sanity filter so the surviving items can be
        // validated 1:1 against the anchored rows; fills nothing when the counts
        // or transcript order don't line up (prefer blank over bad).
        result.lineItems = Self.overlayAnchoredColumnPrices(result.lineItems, text: document.text)
        return result
    }

    /// Whether a line-item name plausibly denotes a purchased product, as opposed
    /// to OCR noise a receipt interleaves with real items. The document recognizer
    /// serializes tables column-by-column, so the "Description" column arrives as a
    /// run of lines that mixes product names with model numbers, warranty/promo SKUs,
    /// free-gift ("FOC") lines, and summary labels — all of which the extractors can
    /// mistake for items. Rejecting them keeps the multi-item picker trustworthy.
    static func isPlausibleProduct(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard trimmed.count >= 3 else { return false }

        // Summary rows and metadata labels.
        if isSummaryLine(trimmed) { return false }
        let metadataLabels = ["order no", "order date", "order number", "delivery date",
                              "delivery time", "sales person", "salesperson", "payment term",
                              "payment method", "customer no", "manual order", "discount",
                              "remarks", "signature", "certificate no", "gst reg", "uen",
                              "ref no", "reference", "qty uom", "unit price", "rebate",
                              "redemption", "redeem"]
        if metadataLabels.contains(where: { lower.contains($0) }) { return false }

        // Section separators like "*** GROUP 2***".
        if trimmed.contains("***") { return false }

        // Free-of-charge gifts / vouchers — bundled, not a purchased device.
        if lower.hasPrefix("foc ") || lower.hasPrefix("free ") || lower.contains("grocery voc") {
            return false
        }

        // Warranty/promo SKU lines such as "NPW~WF (2+3 YRS)".
        if trimmed.contains("~") { return false }
        if lower.contains("yrs") && trimmed.contains("(") { return false }

        // Bare model number / SKU code: a single whitespace-free token that mixes
        // UPPERCASE letters with digits (e.g. FV1410H3BA, GT-F4604EP, XS-20-SLIM).
        // A real product name has spaces/real words, and lowercase product names
        // (e.g. "iPhone15") are kept because their letters aren't all uppercase.
        if !trimmed.contains(" ") {
            let letters = trimmed.filter { $0.isLetter }
            let hasDigit = trimmed.contains { $0.isNumber }
            let allUpper = !letters.isEmpty && letters.allSatisfy { $0.isUppercase }
            let codeLike = trimmed.contains("-") || trimmed.count >= 6
            if hasDigit && allUpper && codeLike { return false }
        }

        return true
    }

    /// Fill blank per-item amounts by locating each item's line in the OCR text
    /// and reading the last money-shaped token on it (e.g. `859.00`). Integer-only
    /// tokens (model numbers, quantities) are ignored — a price must have two
    /// decimal places, keeping with "prefer blank over a made-up number".
    static func overlayTextPrices(_ items: [LineItem], text: String) -> [LineItem] {
        guard items.contains(where: { $0.amount == nil }) else { return items }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)

        return items.map { item in
            guard item.amount == nil else { return item }
            let words = significantWords(item.name)
            guard !words.isEmpty else { return item }

            var best: (score: Int, price: Double)?
            for line in lines {
                if isSummaryLine(line) { continue }
                let lower = line.lowercased()
                let score = words.filter { lower.contains($0) }.count
                guard score > 0, let price = priceOnLine(line) else { continue }
                if best == nil || score > best!.score { best = (score, price) }
            }
            // Require matching at least half the item's words so a stray line with
            // one common word can't donate a wrong price.
            guard let hit = best, hit.score * 2 >= words.count else { return item }
            return LineItem(name: item.name, amount: hit.price, quantity: item.quantity,
                            kind: item.kind, category: item.category,
                            sku: item.sku, unitPrice: item.unitPrice)
        }
    }

    // MARK: - Column-major price fill (anchored)

    /// The serialized per-row price column recovered from a column-major
    /// transcript: one optional price per table row, in row order.
    struct AnchoredPriceColumn {
        var rowPrices: [Double?]
        var firstAnchorIndex: Int
        var moneyLineIndices: Set<Int>
    }

    /// Column-aware per-item price fill for column-major transcripts — the
    /// follow-up the build-14 diagnosis called for. iOS 26's document recognizer
    /// can serialize a receipt table column-by-column, so a description and its
    /// price never share a line and `overlayTextPrices` correctly fills nothing.
    /// Such receipts, however, often carry a repeated per-row cell (e.g. a
    /// location/LCN code) that alternates 1:1 with the unit-price column in the
    /// transcript — a row anchor that recovers each row's price *in row order*.
    ///
    /// Safety gates (all must hold, otherwise nothing is filled):
    /// 1. A strict anchor pattern with ≥3 rows exists.
    /// 2. Every item name occurs in the transcript, in order, BEFORE the price
    ///    column — the signature of a column-major layout. (Row-major receipts
    ///    fail this and keep their same-line fills.)
    /// 3. `items.count ≤ rows`, and item *i* takes row *i*'s price only when the
    ///    independent line-total money run agrees for that row.
    /// 4. Only blank amounts are filled, and only with positive prices.
    static func overlayAnchoredColumnPrices(_ items: [LineItem], text: String) -> [LineItem] {
        guard !items.isEmpty, items.contains(where: { $0.amount == nil }) else { return items }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }

        guard let column = anchoredPriceColumn(in: lines),
              items.count <= column.rowPrices.count else { return items }

        // Column-major check: names appear, in order, before the price column.
        var previousIndex = -1
        for item in items {
            guard let index = firstOccurrence(of: item.name, in: lines),
                  index > previousIndex, index < column.firstAnchorIndex else { return items }
            previousIndex = index
        }

        // The line-total column (a second, independent row-ordered money run)
        // must agree with the unit-price column for any row we fill.
        let totalsRun = longestConsecutiveMoneyRun(in: lines, excluding: column.moneyLineIndices)

        return items.enumerated().map { index, item in
            guard item.amount == nil,
                  let price = column.rowPrices[index], price > 0 else { return item }
            if totalsRun.count >= items.count, index < totalsRun.count,
               abs(totalsRun[index] - price) > 0.005 {
                return item // the two columns disagree for this row — prefer blank
            }
            return LineItem(name: item.name, amount: price, quantity: item.quantity,
                            kind: item.kind, category: item.category,
                            sku: item.sku, unitPrice: item.unitPrice)
        }
    }

    /// Detect the anchored unit-price column: a line value repeating ≥3 times
    /// (one occurrence per table row) with exactly 0 or 1 lone-money lines — and
    /// nothing else — between consecutive occurrences. Returns one optional
    /// price per row. Bails when the line before the first anchor is money (a
    /// price-before-anchor layout would shift every row by one).
    static func anchoredPriceColumn(in lines: [String]) -> AnchoredPriceColumn? {
        let moneyValues: [Double?] = lines.map(lineMoneyValue)

        var occurrences: [String: [Int]] = [:]
        for (index, line) in lines.enumerated() {
            guard moneyValues[index] == nil,
                  line.count >= 2, line.count <= 24,
                  line.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            occurrences[line, default: []].append(index)
        }

        var best: AnchoredPriceColumn?
        for (_, indices) in occurrences where indices.count >= 3 {
            var rowPrices: [Double?] = []
            var moneyIndices: Set<Int> = []
            var valid = true
            var pricedRows = 0

            for k in 0..<indices.count {
                let betweenStart = indices[k] + 1
                let betweenEnd = (k + 1 < indices.count) ? indices[k + 1] : min(indices[k] + 2, lines.count)
                let between = Array(betweenStart..<betweenEnd)

                if k + 1 < indices.count {
                    // Strict alternation: at most one line between anchors, and
                    // if present it must be a lone money line.
                    guard between.count <= 1 else { valid = false; break }
                    if let only = between.first {
                        guard let value = moneyValues[only] else { valid = false; break }
                        rowPrices.append(value)
                        moneyIndices.insert(only)
                        pricedRows += 1
                    } else {
                        rowPrices.append(nil)
                    }
                } else {
                    // Last row: a price only if the very next line is money.
                    if let next = between.first, let value = moneyValues[next] {
                        rowPrices.append(value)
                        moneyIndices.insert(next)
                        pricedRows += 1
                    } else {
                        rowPrices.append(nil)
                    }
                }
            }

            guard valid, pricedRows >= 2 else { continue }
            // Ambiguous layout guard: money immediately before the first anchor
            // means prices could belong to the *preceding* rows.
            let first = indices[0]
            if first > 0, moneyValues[first - 1] != nil { continue }

            if best == nil || rowPrices.count > best!.rowPrices.count {
                best = AnchoredPriceColumn(rowPrices: rowPrices, firstAnchorIndex: first, moneyLineIndices: moneyIndices)
            }
        }
        return best
    }

    /// The value of a line that is a single money token and nothing else
    /// (optionally negative: "- 20.00"). Letters anywhere disqualify the line.
    nonisolated static func lineMoneyValue(_ line: String) -> Double? {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty, !compact.contains(where: { $0.isLetter }) else { return nil }
        let negative = compact.hasPrefix("-") || compact.hasPrefix("−") || compact.hasPrefix("(")
        let unsigned = compact.filter { $0 != "-" && $0 != "−" && $0 != "(" && $0 != ")" }
        guard isMoneyToken(unsigned),
              let value = DocumentStructureOCRService.parseAmount(unsigned) else { return nil }
        return negative ? -value : value
    }

    /// The longest run of consecutive lone-money lines outside `excluding` —
    /// the serialized line-total column on a column-major receipt.
    static func longestConsecutiveMoneyRun(in lines: [String], excluding: Set<Int>) -> [Double] {
        var bestRun: [Double] = []
        var current: [Double] = []
        for (index, line) in lines.enumerated() {
            if !excluding.contains(index), let value = lineMoneyValue(line) {
                current.append(value)
            } else {
                if current.count > bestRun.count { bestRun = current }
                current = []
            }
        }
        if current.count > bestRun.count { bestRun = current }
        return bestRun
    }

    /// First transcript line whose normalized text contains the item name.
    static func firstOccurrence(of name: String, in lines: [String]) -> Int? {
        let normalized = normalizeForMatch(name)
        guard normalized.count >= 3 else { return nil }
        return lines.firstIndex { normalizeForMatch($0).contains(normalized) }
    }

    private static let summaryMarkers = ["total", "subtotal", "sub total", "tax", "gst",
                                         "vat", "balance", "change", "amount due", "rounding",
                                         "小計", "合計", "クレジット", "お釣り"]

    static func isSummaryLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return summaryMarkers.contains { lower.contains($0) }
    }

    /// Lowercased alphanumeric words of length ≥3 — the tokens used to match an
    /// item name against a receipt text line.
    static func significantWords(_ name: String) -> [String] {
        name.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
    }

    /// The last money-shaped token on a line (two decimal places required), parsed
    /// to a Double. Returns nil when the line has no such token.
    static func priceOnLine(_ line: String) -> Double? {
        var last: Double?
        for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            guard isMoneyToken(String(token)),
                  let value = DocumentStructureOCRService.parseAmount(String(token)) else { continue }
            last = value
        }
        return last
    }

    /// True when a token is shaped like a currency amount: digits with a decimal
    /// separator followed by exactly two digits at the end (`859.00`, `1,299.00`,
    /// `$49.90`). Rejects bare integers (`1234`) and codes (`GT-F4502PF`).
    static func isMoneyToken(_ token: String) -> Bool {
        let kept = token.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard kept.count >= 3, let sep = kept.lastIndex(where: { $0 == "." || $0 == "," }) else { return false }
        let tail = kept[kept.index(after: sep)...]
        return tail.count == 2 && tail.allSatisfy(\.isNumber)
    }

    /// Null out any extracted amount whose digits don't appear in the OCR text.
    private func groundAmounts(
        _ result: StructuredExtractionResult,
        text: String
    ) -> StructuredExtractionResult {
        guard !text.isEmpty else { return result }
        var out = result

        if let amount = out.amount.value, !Self.amountAppears(amount, in: text) {
            out.amount = .absent
        }

        out.lineItems = out.lineItems.map { item in
            let amount = item.amount.flatMap { Self.amountAppears($0, in: text) ? $0 : nil }
            let unitPrice = item.unitPrice.flatMap { Self.amountAppears($0, in: text) ? $0 : nil }
            guard amount != item.amount || unitPrice != item.unitPrice else { return item }
            return LineItem(name: item.name, amount: amount, quantity: item.quantity,
                            kind: item.kind, category: item.category, sku: item.sku, unitPrice: unitPrice)
        }
        return out
    }

    /// Whether an amount's digits appear in the OCR text (commas ignored), e.g.
    /// 919.0 matches "919.00" or "919"; a hallucinated 2599.9 matches neither.
    static func amountAppears(_ amount: Double, in text: String) -> Bool {
        // Reject non-finite / out-of-range values up front — `Int(_:)` below traps
        // on NaN/±inf or magnitudes beyond Int range (e.g. a garbled 1e19 amount).
        guard amount.isFinite else { return false }
        let magnitude = abs(amount)
        let normalized = text.replacingOccurrences(of: ",", with: "")

        // Match either the "123.45" or bare-integer form, but only as a STANDALONE
        // number — never as a substring of a larger figure. Without the boundary
        // check a hallucinated "9.00" grounds against the "9.00" inside "919.00",
        // and "9" matches the "9" in "1999"/dates/quantities.
        let twoDecimals = String(format: "%.2f", magnitude)
        if Self.containsStandaloneNumber(twoDecimals, in: normalized) { return true }

        guard magnitude < Double(Int.max) else { return false }
        let intPart = String(Int(magnitude))
        return Self.containsStandaloneNumber(intPart, in: normalized)
    }

    /// True if `number` occurs in `text` not flanked by other digits, so "919"
    /// matches "919" / "$919" / "919.00" but not the "919" inside "29190".
    private static func containsStandaloneNumber(_ number: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: number, range: searchStart..<text.endIndex) {
            let beforeOK = range.lowerBound == text.startIndex
                || !text[text.index(before: range.lowerBound)].isNumber
            let afterOK = range.upperBound == text.endIndex
                || !text[range.upperBound].isNumber
            if beforeOK && afterOK { return true }
            searchStart = range.upperBound
        }
        return false
    }

    /// When no category was extracted, suggest one from the product name via
    /// on-device embeddings. Low confidence — surfaced as a hint, not a fact.
    private func applyCategoryFallback(
        to result: StructuredExtractionResult
    ) -> StructuredExtractionResult {
        guard result.category.value == nil else { return result }
        let basis = result.productName.value
            ?? result.lineItems.first(where: { $0.kind.isRecordWorthy })?.name
        guard let basis, let category = CategoryClassifier.classify(basis) else { return result }
        var out = result
        out.category = ExtractedField(value: category, confidence: .low)
        return out
    }

    /// Overlay structural OCR signals onto a text-derived result.
    private func applyStructure(
        _ structure: DocumentStructure,
        to result: StructuredExtractionResult
    ) -> StructuredExtractionResult {
        var out = result

        // A structurally-read total is authoritative — retire the guesswork.
        if let total = structure.detectedTotal {
            let previous = out.amount.value
            out.amount = ExtractedField(value: total, confidence: .high)
            ExtractionMetrics.recordStructuralTotalOverride(previous: previous, structural: total)
        }

        // Line items: the table's price column is the *real* receipt data. The
        // FM/heuristic line items have cleaner names, but their amounts are often
        // hallucinated (and then blanked by groundAmounts) — so overlay the table
        // amounts onto any item missing one. When the text extractors produced no
        // items at all, take the table's items wholesale.
        if out.lineItems.isEmpty && !structure.tableLineItems.isEmpty {
            out.lineItems = structure.tableLineItems
        } else if !structure.tableLineItems.isEmpty {
            out.lineItems = Self.overlayTableAmounts(out.lineItems, from: structure.tableLineItems)
        }

        return out
    }

    /// Fill in missing per-item amounts from the table's price column. Matches a
    /// text-extractor line item to a priced table row by fuzzy name, falling back
    /// to position when the two lists are the same length. Only *blank* amounts
    /// are filled — an amount the model already grounded in the OCR text is kept.
    static func overlayTableAmounts(_ items: [LineItem], from table: [LineItem]) -> [LineItem] {
        let priced = table.filter { $0.amount != nil }
        guard !priced.isEmpty else { return items }
        let sameLength = items.count == table.count

        return items.enumerated().map { index, item in
            guard item.amount == nil else { return item }
            let match = priced.first { namesMatch($0.name, item.name) }
                ?? (sameLength && table[index].amount != nil ? table[index] : nil)
            guard let amount = match?.amount else { return item }
            return LineItem(name: item.name, amount: amount, quantity: item.quantity,
                            kind: item.kind, category: item.category,
                            sku: item.sku, unitPrice: item.unitPrice)
        }
    }

    /// Loose name equality for matching a clean FM item name against a raw table
    /// cell: lowercase, alphanumerics only, then substring either direction.
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        let na = normalizeForMatch(a), nb = normalizeForMatch(b)
        guard na.count >= 3, nb.count >= 3 else { return false }
        return na.contains(nb) || nb.contains(na)
    }

    private static func normalizeForMatch(_ s: String) -> String {
        s.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    /// Extract structured fields from OCR text.
    ///
    /// When `image` is provided and iOS 27+ is available, the Foundation Model extraction path
    /// uses the image directly (OCRTool + BarcodeReaderTool) rather than the pre-extracted text.
    /// Returns a merged result: Foundation Model values take priority, heuristic values fill gaps.
    func extract(from ocrText: String, image: UIImage? = nil, learningContext: MerchantLearningContext? = nil) async -> StructuredExtractionResult {
        guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Self.logger.info("Empty OCR text — skipping extraction")
            return .empty
        }

        Self.logger.info("Starting extraction pipeline (OCR text: \(ocrText.count, privacy: .public) chars, image: \(image != nil ? "yes" : "no", privacy: .public))")

        // Run both extractions concurrently. FM uses the image when available (iOS 27+);
        // heuristic always uses text (image is unused by the heuristic path).
        async let fmResult = foundationModelService.extract(from: ocrText, image: image, learningContext: learningContext)
        async let heuristicResult = heuristicService.extract(from: ocrText, image: nil, learningContext: learningContext)

        let fm = await fmResult
        let heuristic = await heuristicResult

        // Build combined diagnostics.
        let fmDiag = fm.diagnostics
        let hDiag = heuristic.diagnostics

        let combinedDiag = ExtractionDiagnostics(
            foundationModelAvailable: fmDiag?.foundationModelAvailable ?? false,
            foundationModelRan: fmDiag?.foundationModelRan ?? false,
            foundationModelSkipReason: fmDiag?.foundationModelSkipReason,
            foundationModelFieldCount: fmDiag?.foundationModelFieldCount ?? 0,
            heuristicFieldCount: hDiag?.heuristicFieldCount ?? 0,
            rejectedFields: hDiag?.rejectedFields ?? []
        )

        // If Foundation Model returned nothing useful, use heuristic directly.
        if fm.source == .none {
            Self.logger.info("Foundation Models returned empty — using heuristic-only result (fields: \(combinedDiag.heuristicFieldCount, privacy: .public), rejected: \(combinedDiag.rejectedFields.joined(separator: ","), privacy: .public))")
            var result = heuristic
            result.diagnostics = combinedDiag
            addSentryBreadcrumb(ocrTextLength: ocrText.count, diagnostics: combinedDiag, source: heuristic.source)
            return result
        }

        Self.logger.info("Merging FM (\(combinedDiag.foundationModelFieldCount, privacy: .public) fields) + heuristic (\(combinedDiag.heuristicFieldCount, privacy: .public) fields)")

        // Merge: prefer FM values, fall back to heuristic for missing fields.
        var merged = merge(primary: fm, fallback: heuristic)
        merged.diagnostics = combinedDiag
        addSentryBreadcrumb(ocrTextLength: ocrText.count, diagnostics: combinedDiag, source: fm.source)
        return merged
    }

    // MARK: - Sentry breadcrumbs

    private func addSentryBreadcrumb(
        ocrTextLength: Int,
        diagnostics: ExtractionDiagnostics,
        source: ExtractionSource
    ) {
        let crumb = Breadcrumb()
        crumb.category = "extraction"
        crumb.message = "Pipeline completed"
        crumb.level = .info
        crumb.data = [
            "ocrTextLength": ocrTextLength,
            "fmAvailable": diagnostics.foundationModelAvailable,
            "fmRan": diagnostics.foundationModelRan,
            "fmSkipReason": diagnostics.foundationModelSkipReason ?? "none",
            "fmFieldCount": diagnostics.foundationModelFieldCount,
            "heuristicFieldCount": diagnostics.heuristicFieldCount,
            "rejectedFields": diagnostics.rejectedFields.joined(separator: ","),
            "source": source.rawValue,
        ]
        SentrySDK.addBreadcrumb(crumb)
    }

    // MARK: - Merging

    private func merge(
        primary: StructuredExtractionResult,
        fallback: StructuredExtractionResult
    ) -> StructuredExtractionResult {
        // Prefer FM line items if available (they have better classification);
        // otherwise use heuristic line items.
        let mergedLineItems = primary.lineItems.isEmpty ? fallback.lineItems : primary.lineItems

        return StructuredExtractionResult(
            documentKind: pick(primary.documentKind, fallback.documentKind),
            productName: pick(primary.productName, fallback.productName),
            merchantName: pick(primary.merchantName, fallback.merchantName),
            purchaseDate: pick(primary.purchaseDate, fallback.purchaseDate),
            // For amount, prefer the larger value — the correct total
            // is almost always the largest amount on a receipt. This handles
            // cases where both FM and heuristic extract a subtotal instead
            // of the grand total.
            amount: pickLargerAmount(primary.amount, fallback.amount),
            currency: pick(primary.currency, fallback.currency),
            category: pick(primary.category, fallback.category),
            warrantyDurationMonths: pick(primary.warrantyDurationMonths, fallback.warrantyDurationMonths),
            vatId: pick(primary.vatId, fallback.vatId),
            taxAmount: pick(primary.taxAmount, fallback.taxAmount),
            orderReference: pick(primary.orderReference, fallback.orderReference),
            lineItems: mergedLineItems,
            source: primary.source,
            diagnostics: primary.diagnostics
        )
    }

    /// Pick the primary field if it has a value; otherwise use the fallback.
    private func pick<T>(_ primary: ExtractedField<T>, _ fallback: ExtractedField<T>) -> ExtractedField<T> {
        if primary.value != nil {
            return primary
        }
        return fallback
    }

    /// For amounts, prefer the larger value — the correct total is almost always
    /// the largest reasonable amount on a receipt (grand total > subtotal).
    private func pickLargerAmount(
        _ primary: ExtractedField<Double>,
        _ fallback: ExtractedField<Double>
    ) -> ExtractedField<Double> {
        guard let pVal = primary.value, let fVal = fallback.value else {
            // If only one has a value, use whichever has one
            return primary.value != nil ? primary : fallback
        }
        // Prefer the larger amount (grand total > subtotal)
        return pVal >= fVal ? primary : fallback
    }
}

// MARK: - Convenience bridge to OCRExtractionResult

extension StructuredExtractionResult {
    /// Convert to the existing `OCRExtractionResult` format used by the rest of the app.
    ///
    /// This bridge allows the new extraction pipeline to integrate without changing
    /// every downstream consumer at once. Over time, views can adopt `StructuredExtractionResult`
    /// directly to show per-field confidence.
    func toOCRExtractionResult(recognizedText: String) -> OCRExtractionResult {
        return OCRExtractionResult(
            recognizedText: recognizedText,
            suggestedProductName: productName.value,
            suggestedMerchantName: merchantName.value,
            suggestedPurchaseDate: purchaseDate.value,
            suggestedAmount: amount.value,
            suggestedCurrency: currency.value,
            suggestedCategory: category.value,
            suggestedWarrantyDurationMonths: warrantyDurationMonths.value,
            extractionSource: source,
            suggestedNotes: recognizedText.isEmpty ? nil : "Extracted from scanned document.",
            documentKind: documentKind.value,
            lineItems: lineItems,
            structuredResult: self
        )
    }
}
