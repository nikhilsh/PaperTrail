import Testing
import Foundation
import SwiftData
@testable import PaperTrail

/// Verifies the Settings & Trust wave's data-model additions: new PurchaseRecord
/// fields default cleanly (so existing CloudKit records migrate via lightweight
/// migration) and ReminderSettings defaults hold.
struct TrustModelTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PurchaseRecord.self, Attachment.self, MerchantProfile.self, ProductCategoryMemory.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test @MainActor func newFieldsDefaultCleanly() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // A record created the "old" way — none of the new trust fields supplied —
        // must persist and re-load with sane defaults.
        let record = PurchaseRecord(productName: "Toaster")
        context.insert(record)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<PurchaseRecord>())
        let loaded = try #require(fetched.first)
        #expect(loaded.serialNumber == nil)
        #expect(loaded.coverageSummary == nil)
        #expect(loaded.isRegistered == false)
        #expect(loaded.productImageAttachmentID == nil)
        #expect(loaded.returnWindowNotificationScheduled == false)
    }

    @Test @MainActor func newFieldsRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let pid = UUID()
        let record = PurchaseRecord(
            productName: "Espresso machine",
            serialNumber: "SN-12345",
            coverageSummary: "Parts & labor · compressor 10 yr",
            isRegistered: true,
            productImageAttachmentID: pid
        )
        context.insert(record)
        try context.save()

        let loaded = try #require(try context.fetch(FetchDescriptor<PurchaseRecord>()).first)
        #expect(loaded.serialNumber == "SN-12345")
        #expect(loaded.coverageSummary == "Parts & labor · compressor 10 yr")
        #expect(loaded.isRegistered == true)
        #expect(loaded.productImageAttachmentID == pid)
    }

    @Test func reminderSettingsDefaults() {
        let suite = "TrustModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = ReminderSettings(defaults: defaults)
        #expect(settings.warrantyRemindersEnabled == true)
        #expect(settings.warrantyLeadTime == .twoWeeks)
        #expect(settings.returnWindowRemindersEnabled == true)
        #expect(settings.suggestSupportContacts == true)
        #expect(settings.shareRemindersWithHousehold == true)
    }

    @Test func reminderSettingsPersist() {
        let suite = "TrustModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = ReminderSettings(defaults: defaults)
        settings.warrantyRemindersEnabled = false
        settings.warrantyLeadTime = .oneMonth

        let reloaded = ReminderSettings(defaults: defaults)
        #expect(reloaded.warrantyRemindersEnabled == false)
        #expect(reloaded.warrantyLeadTime == .oneMonth)
    }

    @Test func warrantyLeadTimeDays() {
        #expect(WarrantyLeadTime.oneWeek.days == 7)
        #expect(WarrantyLeadTime.twoWeeks.days == 14)
        #expect(WarrantyLeadTime.oneMonth.days == 30)
    }
}
