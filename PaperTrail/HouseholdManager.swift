import Foundation
import CloudKit
import Observation

/// Household roles.
enum HouseholdRole: String, Codable {
    case owner
    case member
    case invited
}

/// A household participant for display, derived from a CKShare's participants.
struct HouseholdMember: Identifiable, Hashable {
    let id: String
    let name: String
    let email: String?
    let role: HouseholdRole
}

/// Manages the household CKShare (§5) — the CloudKit-sharing primitive that backs
/// invites and the member roster. It shares a dedicated lightweight "Household"
/// record (NOT the SwiftData record zone), so it never forks the app's
/// persistence. Sharing the actual records across accounts (zone sharing) is the
/// heavy, schema-touching step and is gated behind `recordSharingEnabled` until
/// it can be verified on-device.
@MainActor
@Observable
final class HouseholdManager {
    static let shared = HouseholdManager()

    /// Master switch for cross-account record visibility (the zone-sharing step).
    /// Off by default: the invite + roster work, but shared devices don't yet see
    /// each other's records until this is verified on a device.
    static let recordSharingEnabled = false

    private let containerID = "iCloud.nikhilsh.PaperTrail"
    private let householdRecordType = "Household"
    private let householdRecordName = "household-root"

    private(set) var members: [HouseholdMember] = []
    private(set) var lastError: String?

    /// True when the zone-wide share was found in *our* private database (we
    /// created/own `HouseholdZone`), false when it was found via the shared
    /// database (we're a household member). Only meaningful when
    /// `recordSharingEnabled` is `true`; unused on the decoy-share path.
    private(set) var isHouseholdOwner = true

    @ObservationIgnored private lazy var container = CKContainer(identifier: containerID)
    @ObservationIgnored private var cachedShare: CKShare?

    private init() {}

    private var privateDB: CKDatabase { container.privateCloudDatabase }

    /// Load the existing household share (if any) and publish its participants.
    func refresh() async {
        do {
            if Self.recordSharingEnabled {
                if let share = try await fetchExistingZoneShare() {
                    cachedShare = share
                    isHouseholdOwner = true
                    members = Self.members(from: share)
                } else if let share = try await fetchExistingSharedZoneShare() {
                    cachedShare = share
                    isHouseholdOwner = false
                    members = Self.members(from: share)
                } else {
                    members = []
                }
            } else if let share = try await fetchExistingShare() {
                cachedShare = share
                members = Self.members(from: share)
            } else {
                members = []
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Ensure a household root record + CKShare exist, returning the share and
    /// container for `UICloudSharingController`.
    func makeShare() async throws -> (CKShare, CKContainer) {
        if Self.recordSharingEnabled {
            return try await makeZoneShare()
        }

        if let share = cachedShare {
            return (share, container)
        }
        if let share = try await fetchExistingShare() {
            cachedShare = share
            return (share, container)
        }

        let rootID = CKRecord.ID(recordName: householdRecordName)
        let root = CKRecord(recordType: householdRecordType, recordID: rootID)
        root["createdAt"] = Date.now as CKRecordValue

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "PaperTrail Household" as CKRecordValue
        share.publicPermission = .none

        _ = try await privateDB.modifyRecords(saving: [root, share], deleting: [])
        cachedShare = share
        members = Self.members(from: share)
        return (share, container)
    }

    /// Accept a household invite. Called from the CloudKit share-acceptance
    /// delegate chain (`PaperTrail/HouseholdSync/ShareAcceptance.swift`) — this
    /// is the only entry point for becoming a household member, so it's the
    /// path Sentry must be able to explain if acceptance silently fails.
    func acceptShare(metadata: CKShare.Metadata) async {
        guard Self.recordSharingEnabled else { return }
        AppLogger.info("Accepting household share invite", category: "cloud.sharing")
        do {
            _ = try await container.accept(metadata)
            AppLogger.info("Accepted household share invite", category: "cloud.sharing")
        } catch {
            AppLogger.error("Failed to accept household share invite: \(error.localizedDescription)", category: "cloud.sharing")
            lastError = error.localizedDescription
            return
        }
        HouseholdSyncEngine.shared.start()
        await refresh()
    }

    private func fetchExistingShare() async throws -> CKShare? {
        let rootID = CKRecord.ID(recordName: householdRecordName)
        do {
            let root = try await privateDB.record(for: rootID)
            guard let shareRef = root.share else { return nil }
            let shareRecord = try await privateDB.record(for: shareRef.recordID)
            return shareRecord as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    // MARK: - Zone-wide share (flag-on path)

    private func makeZoneShare() async throws -> (CKShare, CKContainer) {
        if let share = cachedShare, isHouseholdOwner {
            return (share, container)
        }

        try await ensureHouseholdZoneExists()

        if let share = try await fetchExistingZoneShare() {
            cachedShare = share
            isHouseholdOwner = true
            members = Self.members(from: share)
            return (share, container)
        }

        let share = CKShare(recordZoneID: HouseholdSchema.ownerZoneID)
        share[CKShare.SystemFieldKey.title] = "Household" as CKRecordValue
        share.publicPermission = .none

        _ = try await privateDB.modifyRecords(saving: [share], deleting: [])
        cachedShare = share
        isHouseholdOwner = true
        members = Self.members(from: share)

        await migrateDecoyShareIfNeeded()

        return (share, container)
    }

    private func ensureHouseholdZoneExists() async throws {
        let zone = CKRecordZone(zoneID: HouseholdSchema.ownerZoneID)
        do {
            _ = try await privateDB.save(zone)
            AppLogger.info("HouseholdZone ready", category: "cloud.sharing")
        } catch {
            AppLogger.error("Failed to save HouseholdZone: \(error.localizedDescription)", category: "cloud.sharing")
            throw error
        }
    }

    /// Owner-side lookup: is there already a zone-wide share for
    /// `HouseholdZone` in our private database?
    private func fetchExistingZoneShare() async throws -> CKShare? {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: HouseholdSchema.ownerZoneID)
        do {
            let record = try await privateDB.record(for: shareID)
            return record as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    /// Member-side lookup: find `HouseholdZone` (someone else's) in our
    /// shared database and fetch its zone-wide share.
    private func fetchExistingSharedZoneShare() async throws -> CKShare? {
        let sharedDB = container.sharedCloudDatabase
        let zones: [CKRecordZone]
        do {
            zones = try await sharedDB.allRecordZones()
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
        guard let zone = zones.first(where: { $0.zoneID.zoneName == HouseholdSchema.zoneName }) else {
            return nil
        }
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone.zoneID)
        do {
            let record = try await sharedDB.record(for: shareID)
            return record as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    /// Best-effort: delete the old decoy `household-root` record + its share
    /// now that a real zone-wide share exists. Never throws — the decoy may
    /// legitimately not exist (flag has been off, no production participants
    /// yet per docs/SHARING_ARCHITECTURE.md), and failure here shouldn't block
    /// the zone share that already succeeded.
    private func migrateDecoyShareIfNeeded() async {
        let rootID = CKRecord.ID(recordName: householdRecordName)
        do {
            let root = try await privateDB.record(for: rootID)
            var toDelete = [rootID]
            if let shareRef = root.share {
                toDelete.append(shareRef.recordID)
            }
            _ = try await privateDB.modifyRecords(saving: [], deleting: toDelete)
            AppLogger.info("Migrated decoy household-root record to zone-wide share", category: "cloud.sharing")
        } catch let ckError as CKError where ckError.code == .unknownItem {
            // No decoy record to migrate — nothing to do.
        } catch {
            AppLogger.error("Decoy household-root migration failed (non-fatal): \(error.localizedDescription)", category: "cloud.sharing")
        }
    }

    private static func members(from share: CKShare) -> [HouseholdMember] {
        share.participants.compactMap { participant in
            let identity = participant.userIdentity
            let components = identity.nameComponents
            let name: String
            if let components {
                let formatter = PersonNameComponentsFormatter()
                let formatted = formatter.string(from: components)
                name = formatted.isEmpty ? "Member" : formatted
            } else {
                name = participant.role == .owner ? "You" : "Member"
            }
            let email = identity.lookupInfo?.emailAddress
            let role: HouseholdRole
            switch (participant.role, participant.acceptanceStatus) {
            case (.owner, _): role = .owner
            case (_, .pending): role = .invited
            default: role = .member
            }
            return HouseholdMember(id: "\(participant.userIdentity.userRecordID?.recordName ?? UUID().uuidString)",
                                   name: name, email: email, role: role)
        }
    }
}
