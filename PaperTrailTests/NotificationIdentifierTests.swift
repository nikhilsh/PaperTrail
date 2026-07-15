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
}
