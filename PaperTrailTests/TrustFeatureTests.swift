import Testing
import Foundation
import SwiftData
import PDFKit
@testable import PaperTrail

/// Coverage for the Settings & Trust wave's logic that previously shipped
/// untested: the export CSV, the Claim Packet PDF, avatar initials, and the
/// honest backup states.
struct TrustFeatureTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PurchaseRecord.self, Attachment.self, MerchantProfile.self, ProductCategoryMemory.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    private func sampleRecord() -> PurchaseRecord {
        PurchaseRecord(
            productName: "LG Washer, \"Dryer\" Combo",
            merchantName: "Gain City",
            purchaseDate: Date(timeIntervalSince1970: 1_747_000_000),
            warrantyExpiryDate: Date(timeIntervalSince1970: 1_810_000_000),
            amount: 1479.0,
            currency: "SGD",
            category: "Appliances",
            room: "Laundry",
            tags: ["white goods"],
            serialNumber: "SN-9XK42",
            coverageSummary: "Parts & labor",
            isRegistered: true
        )
    }

    // MARK: - Export CSV (§3)

    @Test @MainActor func csvIncludesTrustFieldsAndEscapes() throws {
        let container = try makeContainer()
        let record = sampleRecord()
        container.mainContext.insert(record)

        let csv = ExportService.makeCSV(records: [record])
        let lines = csv.split(separator: "\n").map(String.init)

        #expect(lines.count == 2)
        #expect(lines[0].contains("Serial Number"))
        #expect(lines[0].contains("Coverage"))
        #expect(lines[0].contains("Registered"))

        // Commas + quotes in the product name must be CSV-escaped.
        #expect(lines[1].contains("\"LG Washer, \"\"Dryer\"\" Combo\""))
        #expect(lines[1].contains("SN-9XK42"))
        #expect(lines[1].contains("Parts & labor"))
        #expect(lines[1].contains("Yes"))
        #expect(lines[1].contains("1479.00"))
    }

    @Test @MainActor func csvEmitsOneRowPerRecord() throws {
        let container = try makeContainer()
        let records = (1...3).map { PurchaseRecord(productName: "Item \($0)") }
        records.forEach { container.mainContext.insert($0) }

        let csv = ExportService.makeCSV(records: records)
        #expect(csv.split(separator: "\n").count == 4) // header + 3 rows
    }

    // MARK: - Claim Packet (§9)

    @Test @MainActor func claimPacketDocumentNumberIsDeterministic() throws {
        let container = try makeContainer()
        let record = sampleRecord()
        container.mainContext.insert(record)

        let first = ClaimPacketPDF.documentNumber(for: record)
        let second = ClaimPacketPDF.documentNumber(for: record)
        #expect(first == second)
        #expect(first.hasPrefix("PT-"))
        #expect(first.count == 11) // "PT-" + 8 uuid hex chars
    }

    @Test @MainActor func claimPacketRendersOnePagePDF() throws {
        let container = try makeContainer()
        let record = sampleRecord()
        container.mainContext.insert(record)

        let url = try #require(ClaimPacketPDF.generate(record: record, attachments: []))
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 1)
        // The rendered text layer should carry the key claim fields.
        let pageText = document.page(at: 0)?.string ?? ""
        #expect(pageText.contains("PROOF OF PURCHASE"))
        #expect(pageText.contains("SN-9XK42"))
    }

    @Test @MainActor func recordPDFAppendsAProofPagePerImage() throws {
        let container = try makeContainer()
        let record = sampleRecord()
        container.mainContext.insert(record)

        // No attachments → just the claim-packet cover page.
        let doc = try #require(ExportService.makeRecordPDF(record: record, attachments: []))
        #expect(doc.pageCount == 1)
    }

    // MARK: - Avatar initials (§1)

    @Test func avatarInitials() {
        #expect("Alex Rivera".ptInitials == "AR")
        #expect("nikhil".ptInitials == "N")
        #expect("Mary Jane Watson".ptInitials == "MJ") // first two parts only
        #expect("".ptInitials == "")
    }

    // MARK: - Honest backup states (§7)

    @Test func backupStateCopyMatchesSpec() {
        #expect(BackupState.synced(relative: "just now").text == "Backed up · just now")
        #expect(BackupState.syncing(remaining: 2).text == "Backing up · 2 to go")
        #expect(BackupState.paused.text == "Backup paused · tap to retry")
        #expect(BackupState.paused.isPaused)
        #expect(!BackupState.synced(relative: "just now").isPaused)
    }

    @Test @MainActor func localFallbackReadsAsPaused() {
        let state = currentBackupState(
            syncManager: CloudImageSyncManager.shared,
            activeSyncBackend: "Local fallback",
            lastSync: nil
        )
        #expect(state.isPaused)

        let healthy = currentBackupState(
            syncManager: CloudImageSyncManager.shared,
            activeSyncBackend: "CloudKit",
            lastSync: nil
        )
        #expect(healthy.text == "Backed up · just now")
    }
}
