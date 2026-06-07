import Foundation
import UIKit
import PDFKit

/// Builds a real, no-lock-in export bundle (§3): a CSV of every record, a
/// full-quality PDF per record (claim-packet cover page + a page per proof
/// image), and a combined "proof book" PDF — zipped for the share sheet or
/// Save-to-Files. Exports **all** records, not a sample.
///
/// MainActor-isolated because it reads SwiftData `@Model` objects (and their
/// on-disk images) directly; callers are already on the main actor.
@MainActor
enum ExportService {

    struct Summary {
        let recordCount: Int
        let documentCount: Int
    }

    static func summary(records: [PurchaseRecord], attachments: [Attachment]) -> Summary {
        Summary(recordCount: records.count, documentCount: attachments.count)
    }

    /// Build the export bundle and return a `.zip` file URL.
    static func buildBundle(records: [PurchaseRecord], allAttachments: [Attachment]) async throws -> URL {
        let fm = FileManager.default
        let stageDir = fm.temporaryDirectory.appendingPathComponent("PaperTrailExport-\(UUID().uuidString)", isDirectory: true)
        let pdfDir = stageDir.appendingPathComponent("records", isDirectory: true)
        try fm.createDirectory(at: pdfDir, withIntermediateDirectories: true)

        // 1. CSV of all records.
        let csv = makeCSV(records: records)
        try csv.data(using: .utf8)?.write(to: stageDir.appendingPathComponent("records.csv"))

        // 2. Per-record PDFs + accumulate into the proof book.
        // Index attachments by record once (O(R+A)) instead of re-scanning the full
        // attachment list for every record (O(R×A)).
        let attachmentsByRecord = Dictionary(grouping: allAttachments, by: { $0.recordID })
        let proofBook = PDFDocument()
        for record in records {
            let recordAttachments = attachmentsByRecord[record.id] ?? []
            guard let doc = makeRecordPDF(record: record, attachments: recordAttachments) else { continue }
            let safe = safeFilename(record.productName)
            let recordURL = pdfDir.appendingPathComponent("\(safe)-\(ClaimPacketPDF.documentNumber(for: record)).pdf")
            doc.write(to: recordURL)
            // Append every page to the combined proof book.
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) {
                    proofBook.insert(page, at: proofBook.pageCount)
                }
            }
        }
        if proofBook.pageCount > 0 {
            proofBook.write(to: stageDir.appendingPathComponent("proof-book.pdf"))
        }

        // 3. A short README so the export is self-describing.
        let readme = """
        PaperTrail export
        Generated \(ISO8601DateFormatter().string(from: .now))

        records.csv      — every field for all \(records.count) records
        records/         — one full-quality PDF per record (proof of purchase + warranty + images)
        proof-book.pdf   — all records combined into one printable document

        Your records live in your own iCloud. PaperTrail's servers never see them —
        this export is the complete, readable copy.
        """
        try readme.data(using: .utf8)?.write(to: stageDir.appendingPathComponent("README.txt"))

        // 4. Zip via NSFileCoordinator (same approach as RecordSharingManager).
        let zipURL = fm.temporaryDirectory.appendingPathComponent("PaperTrail-export.zip")
        try? fm.removeItem(at: zipURL)

        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var result: URL?
        coordinator.coordinate(readingItemAt: stageDir, options: .forUploading, error: &coordError) { url in
            do {
                try fm.copyItem(at: url, to: zipURL)
                result = zipURL
            } catch {
                AppLogger.error("Export zip copy failed: \(error)", category: "sharing")
            }
        }
        if let coordError { throw coordError }
        try? fm.removeItem(at: stageDir)

        guard let result else { throw ExportError.bundleFailed }
        return result
    }

    // MARK: - CSV

    static func makeCSV(records: [PurchaseRecord]) -> String {
        let header = ["Product", "Merchant", "Purchase Date", "Amount", "Currency",
                      "Category", "Room", "Tags", "Serial Number", "Coverage",
                      "Registered", "Warranty Expiry", "Notes"]
        var rows = [header.map(csvEscape).joined(separator: ",")]
        let dateFmt = ISO8601DateFormatter()
        dateFmt.formatOptions = [.withFullDate]
        for r in records {
            // Built as explicitly-typed locals (not one big literal) so the
            // type-checker doesn't time out on the mixed optional/ternary array.
            let purchase: String = r.purchaseDate.map { dateFmt.string(from: $0) } ?? ""
            let amount: String = r.amount.map { String(format: "%.2f", $0) } ?? ""
            let expiry: String = r.warrantyExpiryDate.map { dateFmt.string(from: $0) } ?? ""
            let registered: String = r.isRegistered ? "Yes" : "No"
            var cells: [String] = []
            cells.append(r.productName)
            cells.append(r.merchantName ?? "")
            cells.append(purchase)
            cells.append(amount)
            cells.append(r.currency ?? "")
            cells.append(r.category ?? "")
            cells.append(r.room ?? "")
            cells.append(r.tags.joined(separator: "; "))
            cells.append(r.serialNumber ?? "")
            cells.append(r.coverageSummary ?? "")
            cells.append(registered)
            cells.append(expiry)
            cells.append(r.notes ?? "")
            rows.append(cells.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: - Per-record PDF (claim packet cover + full-quality image pages)

    static func makeRecordPDF(record: PurchaseRecord, attachments: [Attachment]) -> PDFDocument? {
        let doc: PDFDocument
        if let coverURL = ClaimPacketPDF.generate(record: record, attachments: attachments),
           let coverDoc = PDFDocument(url: coverURL) {
            doc = coverDoc
        } else {
            doc = PDFDocument()
        }
        // Append a full-quality page per proof image.
        for attachment in attachments {
            guard let image = attachment.image, let page = PDFPage(image: image) else { continue }
            doc.insert(page, at: doc.pageCount)
        }
        return doc.pageCount > 0 ? doc : nil
    }

    private static func safeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        return String(cleaned.prefix(40)).trimmingCharacters(in: .whitespaces)
    }
}

enum ExportError: LocalizedError {
    case bundleFailed
    var errorDescription: String? {
        switch self {
        case .bundleFailed: "Couldn't build the export bundle."
        }
    }
}
