import Testing
import Foundation
@testable import PaperTrail

/// Pure logic tests for `NotificationManager`'s identifier builders — the
/// UUID-keyed format that replaced the old `persistentModelID`-keyed one (a
/// temporary ID at schedule time that never matched the permanent one used by
/// later removal calls, leaking notifications). No `UNUserNotificationCenter`
/// access here; that requires a device/simulator with notification entitlements.
struct NotificationIdentifierTests {

    // MARK: - Format

    @Test func warrantyIdentifierFormat() {
        let id = UUID()
        #expect(NotificationManager.warrantyIdentifier(recordID: id, offsetDays: 30) == "warranty-\(id.uuidString)-30d")
        #expect(NotificationManager.warrantyIdentifier(recordID: id, offsetDays: 0) == "warranty-\(id.uuidString)-0d")
    }

    @Test func returnWindowIdentifierFormat() {
        let id = UUID()
        #expect(NotificationManager.returnWindowIdentifier(recordID: id, offsetDays: 3) == "return-window-\(id.uuidString)-3d")
        #expect(NotificationManager.returnWindowIdentifier(recordID: id, offsetDays: 0) == "return-window-\(id.uuidString)-0d")
    }

    @Test func warrantyIdentifiersCoversAllOffsets() {
        let id = UUID()
        let identifiers = NotificationManager.warrantyIdentifiers(recordID: id)
        #expect(identifiers.count == NotificationManager.warrantyOffsets.count)
        for offset in NotificationManager.warrantyOffsets {
            #expect(identifiers.contains(NotificationManager.warrantyIdentifier(recordID: id, offsetDays: offset)))
        }
    }

    @Test func returnWindowIdentifiersCoversAllOffsets() {
        let id = UUID()
        let identifiers = NotificationManager.returnWindowIdentifiers(recordID: id)
        #expect(identifiers.count == NotificationManager.returnWindowOffsets.count)
        for offset in NotificationManager.returnWindowOffsets {
            #expect(identifiers.contains(NotificationManager.returnWindowIdentifier(recordID: id, offsetDays: offset)))
        }
    }

    // MARK: - UUID round trip (new format)

    @Test func warrantyIdentifierRoundTripsUUID() {
        let id = UUID()
        for offset in NotificationManager.warrantyOffsets {
            let identifier = NotificationManager.warrantyIdentifier(recordID: id, offsetDays: offset)
            #expect(NotificationManager.recordID(fromCurrentFormatIdentifier: identifier) == id)
        }
    }

    @Test func returnWindowIdentifierRoundTripsUUID() {
        let id = UUID()
        for offset in NotificationManager.returnWindowOffsets {
            let identifier = NotificationManager.returnWindowIdentifier(recordID: id, offsetDays: offset)
            #expect(NotificationManager.recordID(fromCurrentFormatIdentifier: identifier) == id)
        }
    }

    // MARK: - Old format is distinguishable / never parses as current

    @Test func oldPersistentModelIDStyleIdentifierDoesNotParse() {
        // Old format: "<persistentModelID description>-warranty-<days>" (no "d"
        // suffix, id comes first) — never starts with the new "warranty-"/
        // "return-window-" prefix, so it must not parse as current-format.
        let oldWarranty = "zzzzz-PurchaseRecord-p123-warranty-30"
        let oldReturnWindow = "zzzzz-PurchaseRecord-p123-return-window-3"
        let oldReturnWindowLegacy = "zzzzz-PurchaseRecord-p123-return-window"

        #expect(NotificationManager.recordID(fromCurrentFormatIdentifier: oldWarranty) == nil)
        #expect(NotificationManager.recordID(fromCurrentFormatIdentifier: oldReturnWindow) == nil)
        #expect(NotificationManager.recordID(fromCurrentFormatIdentifier: oldReturnWindowLegacy) == nil)
    }

    @Test func malformedUUIDInNewPositionDoesNotParse() {
        #expect(NotificationManager.recordID(fromCurrentFormatIdentifier: "warranty-not-a-uuid-30d") == nil)
        #expect(NotificationManager.recordID(fromCurrentFormatIdentifier: "unrelated-identifier") == nil)
    }

    @Test func reminderCategoriesCoversBothFamilies() {
        #expect(NotificationManager.reminderCategories.contains("WARRANTY_EXPIRY"))
        #expect(NotificationManager.reminderCategories.contains("RETURN_WINDOW"))
        #expect(NotificationManager.reminderCategories.count == 2)
    }

    // MARK: - Notification budget (DESIGN_LANGUAGE.md §8: exactly one reminder
    // per record, per family) — via the pure `*ReminderPlan` functions, since
    // the actual scheduling touches `UNUserNotificationCenter`.

    @Test func warrantyPlanProducesExactlyOneReminderAtTheChosenLeadTime() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let record = PurchaseRecord(
            productName: "Fridge",
            warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 60, to: now)
        )
        let plan = try #require(NotificationManager.warrantyReminderPlan(for: record, leadDays: 14, now: now))
        #expect(plan.leadDays == 14)
        #expect(plan.identifier == NotificationManager.warrantyIdentifier(recordID: record.id, offsetDays: 14))

        // No matter the lead time, it's always exactly one plan — never the
        // old 30/14/7/0 multi-reminder set.
        for lead in [7, 14, 30] {
            let leadPlan = NotificationManager.warrantyReminderPlan(for: record, leadDays: lead, now: now)
            #expect(leadPlan?.leadDays == lead)
        }
    }

    @Test func warrantyPlanIsNilWhenTheLeadTimeWouldAlreadyBeInThePast() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Expires in 5 days — a 30-day lead would fire in the past.
        let record = PurchaseRecord(
            productName: "Fridge",
            warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 5, to: now)
        )
        #expect(NotificationManager.warrantyReminderPlan(for: record, leadDays: 30, now: now) == nil)
    }

    @Test func returnWindowPlanIsAlwaysExactlyOneAtThreeDaysBeforeDeadline() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let record = PurchaseRecord(
            productName: "Blender",
            purchaseDate: now,
            returnWindowDays: 30
        )
        let plan = try #require(NotificationManager.returnWindowReminderPlan(for: record, now: now))
        #expect(plan.leadDays == NotificationManager.returnWindowLeadDays)
        #expect(plan.leadDays == 3)
        #expect(plan.identifier == NotificationManager.returnWindowIdentifier(recordID: record.id, offsetDays: 3))
    }

    @Test func returnWindowPlanIsNilWithNoWindowOrPastDeadline() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let noWindow = PurchaseRecord(productName: "No window", purchaseDate: now)
        #expect(NotificationManager.returnWindowReminderPlan(for: noWindow, now: now) == nil)

        let alreadyClosed = PurchaseRecord(
            productName: "Closed",
            purchaseDate: Calendar.current.date(byAdding: .day, value: -30, to: now),
            returnWindowDays: 14
        )
        #expect(NotificationManager.returnWindowReminderPlan(for: alreadyClosed, now: now) == nil)
    }

    // MARK: - rescheduleAll respects settings (`eligibleForReschedule`, pure)

    @Test func eligibleForRescheduleExcludesARecordWhenItsSettingIsOff() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let warrantyRecord = PurchaseRecord(
            productName: "TV",
            warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 20, to: now)
        )
        let returnWindowRecord = PurchaseRecord(
            productName: "Blender",
            purchaseDate: now,
            returnWindowDays: 10
        )

        // Both settings on: both records eligible.
        let bothOn = NotificationManager.eligibleForReschedule(
            records: [warrantyRecord, returnWindowRecord],
            warrantyRemindersEnabled: true,
            returnWindowRemindersEnabled: true
        )
        #expect(Set(bothOn.map(\.id)) == Set([warrantyRecord.id, returnWindowRecord.id]))

        // Warranty reminders off: the warranty-only record drops out.
        let warrantyOff = NotificationManager.eligibleForReschedule(
            records: [warrantyRecord, returnWindowRecord],
            warrantyRemindersEnabled: false,
            returnWindowRemindersEnabled: true
        )
        #expect(warrantyOff.map(\.id) == [returnWindowRecord.id])

        // Both off: nothing eligible.
        let bothOff = NotificationManager.eligibleForReschedule(
            records: [warrantyRecord, returnWindowRecord],
            warrantyRemindersEnabled: false,
            returnWindowRemindersEnabled: false
        )
        #expect(bothOff.isEmpty)
    }

    @Test func eligibleForRescheduleOrdersSoonestFirst() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let far = PurchaseRecord(productName: "Far", warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 90, to: now))
        let soon = PurchaseRecord(productName: "Soon", warrantyExpiryDate: Calendar.current.date(byAdding: .day, value: 10, to: now))

        let eligible = NotificationManager.eligibleForReschedule(
            records: [far, soon],
            warrantyRemindersEnabled: true,
            returnWindowRemindersEnabled: true
        )
        #expect(eligible.map(\.productName) == ["Soon", "Far"])
    }
}
