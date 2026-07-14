import CloudKit
import Foundation

/// Static CloudKit schema for the household record-sharing pipeline
/// (Milestone 4 — see docs/SHARING_ARCHITECTURE.md). Sharing is zone-wide:
/// `HouseholdZone` lives in the owner's private database and every record
/// inside it is visible to every household participant via a single
/// `CKShare(recordZoneID:)` (added in Phase 2, `HouseholdManager`).
///
/// Record types here are ours to name — `SharedPurchaseRecord` /
/// `SharedAttachment` — deliberately distinct from the `CD_*` types SwiftData's
/// CloudKit mirroring generates, so the two sync paths never collide.
enum HouseholdSchema {

    /// The custom record zone every mirrored household record lives in.
    static let zoneName = "HouseholdZone"

    /// The zone ID as it exists on the owner's own device (private database).
    /// Members reach the same zone through the shared database, addressed by
    /// the owner's actual `CKRecord.ID.zoneID` (not this convenience value).
    static var ownerZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    enum RecordType {
        static let purchaseRecord = "SharedPurchaseRecord"
        static let attachment = "SharedAttachment"
        /// Zone-resident settings record (Fix 9) — carries policy that must be
        /// consistent across every owner device, not left to a per-device
        /// `UserDefaults` toggle. See `HouseholdCache.shareWholeLibrarySetting`.
        static let settings = "HouseholdSettings"
    }

    /// Field keys mirroring `PurchaseRecord` 1:1, minus the two device-local
    /// notification-bookkeeping flags (`warrantyNotificationScheduled`,
    /// `returnWindowNotificationScheduled`) — see `SharedPurchaseRecordDTO`.
    enum PurchaseField: String {
        case id
        case productName
        case merchantName
        case purchaseDate
        case warrantyExpiryDate
        case notes
        case amount
        case currency
        case category
        case room
        case tagsRaw
        case supportProviderName
        case supportPhoneNumber
        case supportConfidence
        case supportNote
        case returnWindowDays
        case serialNumber
        case coverageSummary
        case isRegistered
        case productImageAttachmentID
        case createdAt
        case updatedAt
    }

    /// Field keys mirroring `Attachment` 1:1, plus `asset` (Phase 4) — the
    /// `CKAsset` field carrying the attachment's image, uploaded/downloaded
    /// alongside the metadata below rather than through `CloudImageSyncManager`.
    enum AttachmentField: String {
        case id
        // "recordID" is a CKRecord reserved key name (NSInvalidArgumentException
        // at runtime), so the FK to PurchaseRecord.id travels as purchaseRecordID.
        case recordID = "purchaseRecordID"
        case typeRaw
        case localFilename
        case ocrText
        case createdAt
        case asset
    }

    /// Deterministic `CKRecord.ID` record names, mirroring
    /// `CloudImageSyncManager.recordName(for:)`'s `"img-<uuid>"` convention.
    enum RecordName {
        static func purchaseRecord(_ id: UUID) -> String { "rec-\(id.uuidString)" }
        static func attachment(_ id: UUID) -> String { "att-\(id.uuidString)" }
        /// Singleton settings record — one per zone, no id suffix.
        static let settings = "household-settings"
    }

    /// Field keys for the zone-resident `HouseholdSettings` record (Fix 9).
    enum SettingsField: String {
        case shareWholeLibrary
    }
}
