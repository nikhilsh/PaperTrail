import Foundation
import OSLog
import Vision

// MARK: - OCR document payload

/// The output of the OCR layer: best-available text plus optional *structure*.
///
/// Previously the pipeline received a flat `String` (newline-joined Vision
/// lines), discarding reading order and table layout — which is why the
/// pipeline had to *reconstruct* "which number is the grand total" with the
/// `pickLargerAmount` hack. `OCRDocument` carries that structure forward when
/// iOS 26's `RecognizeDocumentsRequest` is available, and degrades to plain
/// text everywhere else.
struct OCRDocument: Sendable {
    /// Plain text for the downstream extractors. Structure-aware (reading order
    /// preserved) when produced by the document recognizer; otherwise the
    /// newline-joined `VNRecognizeTextRequest` output.
    var text: String

    /// Structured signals (tables, typed entities) when available.
    var structure: DocumentStructure?

    static func plain(_ text: String) -> OCRDocument {
        OCRDocument(text: text, structure: nil)
    }
}

/// Structured signals extracted directly by Vision's document recognizer.
struct DocumentStructure: Sendable {
    /// Tables as row-major cell text. A receipt's item × price columns arrive
    /// already aligned instead of interleaved.
    var tables: [OCRTable]

    /// The grand total, when it can be read *structurally* (e.g. the amount cell
    /// on the row whose label says "Total"). When present, the pipeline can stop
    /// guessing which number is the total.
    var detectedTotal: Double?

    /// A purchase/transaction date surfaced by Vision's data detectors.
    var detectedDate: Date?

    /// Line items reconstructed from table rows (name + amount columns).
    var tableLineItems: [LineItem]

    /// True when a total was read structurally — the signal that lets the
    /// pipeline retire the `pickLargerAmount` heuristic for this scan.
    var hasStructuralTotal: Bool { detectedTotal != nil }
}

/// A single table as row-major cell strings.
struct OCRTable: Sendable {
    var rows: [[String]]
}

// MARK: - Structured OCR service

/// Wraps iOS 26's `RecognizeDocumentsRequest` to return a structured
/// `OCRDocument`. Returns `nil` when the API is unavailable or fails, so the
/// caller can fall back to the legacy `VNRecognizeTextRequest` path.
///
/// This is the only place that touches the iOS 26 document recognition API,
/// against these symbols (per Apple's "Recognizing tables within a document"):
///   • `RecognizeDocumentsRequest()` and `perform(on:)` → `[DocumentObservation]`
///   • `observation.document` → `DocumentObservation.Container`
///   • `container.text.transcript` → full plain text
///   • `container.tables` → `[Table]`; `table.rows`; `cell.content.text.transcript`
/// The rest of the overhaul does not depend on these symbols — only this file.
struct DocumentStructureOCRService: Sendable {

    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "extraction.ocr.structured")

    /// Attempt structured recognition. Returns `nil` to signal "fall back to legacy OCR".
    func recognize(_ cgImage: CGImage) async -> OCRDocument? {
        guard #available(iOS 26.0, *) else { return nil }
        return await Self.recognizeStructured(cgImage)
    }

    @available(iOS 26.0, *)
    private static func recognizeStructured(_ cgImage: CGImage) async -> OCRDocument? {
        do {
            let request = RecognizeDocumentsRequest()
            let observations = try await request.perform(on: cgImage)
            guard let document = observations.first?.document else {
                logger.info("Structured OCR returned no document — falling back")
                return nil
            }

            // Full document text: the container exposes a `text` object whose
            // `.transcript` is the plain string (mirrors `cell.content.text`).
            let transcript = document.text.transcript
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            // Walk tables: `table.rows` is a sequence of rows, each row a sequence
            // of cells, each cell's text at `cell.content.text.transcript`.
            var tables: [OCRTable] = []
            for table in document.tables {
                var rows: [[String]] = []
                for row in table.rows {
                    let cells = row.map {
                        $0.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    rows.append(cells)
                }
                if !rows.isEmpty { tables.append(OCRTable(rows: rows)) }
            }

            let detectedTotal = Self.detectTotal(in: tables)
            let lineItems = Self.lineItems(from: tables)

            logger.info("Structured OCR: \(tables.count, privacy: .public) tables, total=\(detectedTotal != nil, privacy: .public), items=\(lineItems.count, privacy: .public)")

            // TEMP DIAGNOSTIC (remove once auto-fill is fixed): when structured OCR
            // runs but finds no usable table total, transmit the counts so we can
            // tell "recognizer found 0 tables" from "found tables but parsing missed
            // the cells". Breadcrumbs don't transmit without an error event, so use
            // AppLogger.error (it captures a Sentry message).
            if detectedTotal == nil {
                let cellCount = tables.reduce(0) { $0 + $1.rows.reduce(0) { $0 + $1.count } }
                let pricedItems = lineItems.filter { $0.amount != nil }.count
                AppLogger.error(
                    "Structured OCR no total: tables=\(tables.count) cells=\(cellCount) items=\(lineItems.count) priced=\(pricedItems)",
                    category: "extraction.ocr.structured_empty",
                    tags: [
                        "table_count": String(tables.count),
                        "cell_count": String(cellCount),
                        "table_items": String(lineItems.count),
                        "table_priced": String(pricedItems),
                        "transcript_len": String(transcript.count),
                    ]
                )
            }

            let structure = DocumentStructure(
                tables: tables,
                detectedTotal: detectedTotal,
                detectedDate: nil, // dates are parsed from the (improved) transcript downstream
                tableLineItems: lineItems
            )
            return OCRDocument(text: transcript, structure: structure)
        } catch {
            logger.warning("Structured OCR failed: \(error.localizedDescription, privacy: .public) — falling back to legacy OCR")
            return nil
        }
    }

    // MARK: - Structural total & line items (pure, no Vision API — safe)

    /// Find the grand total structurally: the amount on a row whose label cell
    /// mentions "total" (preferring "grand total" / "total due" / "amount due"
    /// over "subtotal"). This replaces the `pickLargerAmount` guesswork.
    static func detectTotal(in tables: [OCRTable]) -> Double? {
        let strongLabels = ["grand total", "total due", "amount due", "balance due", "total amount", "total"]
        let weakLabels = ["subtotal", "sub total", "sub-total"]

        var best: (rank: Int, value: Double)?
        for table in tables {
            for row in table.rows {
                let label = row.joined(separator: " ").lowercased()
                // Skip subtotal rows — they are the classic false positive.
                if weakLabels.contains(where: { label.contains($0) }) && !strongLabels.dropLast().contains(where: { label.contains($0) }) {
                    continue
                }
                guard let rank = strongLabels.firstIndex(where: { label.contains($0) }) else { continue }
                // Take the largest parseable amount on this row as the total value.
                let amounts = row.compactMap(parseAmount)
                guard let value = amounts.max() else { continue }
                // Lower rank index = stronger label.
                if best == nil || rank < best!.rank {
                    best = (rank, value)
                }
            }
        }
        return best?.value
    }

    /// Reconstruct line items from table rows: a name-ish cell + an amount cell.
    /// Skips total/subtotal/tax summary rows.
    static func lineItems(from tables: [OCRTable]) -> [LineItem] {
        let summaryMarkers = ["total", "subtotal", "sub total", "tax", "gst", "vat", "balance", "change", "amount due", "rounding"]
        var items: [LineItem] = []
        for table in tables {
            for row in table.rows {
                let joined = row.joined(separator: " ").lowercased()
                if summaryMarkers.contains(where: { joined.contains($0) }) { continue }

                // Name = the longest cell with letters. Amount = the LAST parseable
                // money cell — receipt tables put the line total in the rightmost
                // column, so prefer it over a (possibly larger) unit-price column.
                let nameCell = row
                    .filter { $0.contains(where: { $0.isLetter }) }
                    .max(by: { $0.count < $1.count })
                let amount = row.compactMap(parseAmount).last

                guard let name = nameCell?.trimmingCharacters(in: .whitespacesAndNewlines),
                      name.count >= 3 else { continue }

                items.append(LineItem(name: name, amount: amount, quantity: 1, kind: .unknown))
            }
        }
        return items
    }

    /// Parse a currency-ish string ("$1,299.00", "1299.00", "SGD 49.90") to a Double.
    static func parseAmount(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: { $0.isNumber }) else { return nil }
        // Keep digits, dot, comma, minus; drop currency symbols/letters.
        var stripped = trimmed.unicodeScalars.filter {
            CharacterSet(charactersIn: "0123456789.,-").contains($0)
        }.map(String.init).joined()
        // Remove thousands separators: a comma followed by exactly 3 digits.
        // Heuristic: if there's both a comma and a dot, treat comma as thousands.
        if stripped.contains(",") && stripped.contains(".") {
            stripped = stripped.replacingOccurrences(of: ",", with: "")
        } else if stripped.contains(",") && !stripped.contains(".") {
            // European decimal comma → dot (only one comma, 2 trailing digits).
            let parts = stripped.split(separator: ",")
            if parts.count == 2 && parts[1].count == 2 {
                stripped = stripped.replacingOccurrences(of: ",", with: ".")
            } else {
                stripped = stripped.replacingOccurrences(of: ",", with: "")
            }
        }
        guard let value = Double(stripped), value > 0 else { return nil }
        return value
    }
}
