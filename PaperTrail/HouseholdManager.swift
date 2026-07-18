import Foundation
import CloudKit
import Observation
import UIKit

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

/// Errors specific to the zone-wide share (flag-on) path — see
/// `HouseholdManager.makeZoneShare()`.
enum HouseholdError: LocalizedError {
    /// Fix 6: dual-role guard. This device is already a household MEMBER
    /// (found via the shared database); creating a second, owned zone share
    /// would give one device two roles and risk a raced `refresh()` wiping
    /// the shared-in cache.
    case alreadyInHousehold
    /// Fix 5: `modifyRecords` didn't return a save result for the share
    /// record we asked it to save — treat as a failure rather than assuming
    /// success.
    case missingShareSaveResult
    /// Fix 5: the saved record CloudKit handed back wasn't a `CKShare`.
    case unexpectedShareRecordType
    /// PaperTrail Plus gate (docs/MONETIZATION.md): the first household
    /// member is free, but growing beyond that requires Plus. Thrown by
    /// `makeShare()` before it ever touches CloudKit — `HouseholdView.invite`
    /// catches this specific case and presents `PaywallView` instead of the
    /// generic error alert. Only reachable when `PlusConfig.enabled` is true.
    case plusRequired

    var errorDescription: String? {
        switch self {
        case .alreadyInHousehold:
            "You're already in a household — leave it before creating your own."
        case .missingShareSaveResult:
            "CloudKit didn't confirm the household share was saved."
        case .unexpectedShareRecordType:
            "CloudKit returned an unexpected record for the household share."
        case .plusRequired:
            "Sharing with more than one person is part of PaperTrail Plus."
        }
    }
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
    static let recordSharingEnabled = true

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

    /// True once a zone-wide (or decoy) share has been created/found — used by
    /// `HouseholdMirrorCoordinator` to gate reconciliation: mirroring only
    /// makes sense once there's an actual share to mirror into.
    var hasActiveShare: Bool { cachedShare != nil }

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
                    // Fix 6: neither lookup found a share — the previous
                    // code left `cachedShare` stale here, so `hasActiveShare`
                    // kept lying "true" for the rest of the session after a
                    // share was deleted/revoked upstream.
                    cachedShare = nil
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
        // PaperTrail Plus gate: growing a household past its first member
        // (any share that already has ≥1 non-owner participant) requires
        // Plus. Checked before either share path below, so both the
        // zone-share (flag-on) and decoy-share (flag-off record-sharing)
        // paths are covered by one gate. No-op entirely while
        // `PlusConfig.enabled` is false.
        if PlusConfig.enabled {
            let nonOwnerCount = members.filter { $0.role != .owner }.count
            if nonOwnerCount >= 1 && !PlusEntitlements.shared.canUseHousehold {
                let error = HouseholdError.plusRequired
                lastError = error.errorDescription
                throw error
            }
        }

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
        brandShare(share)
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
            // The accept metadata is the ONE place iOS hands us the owner's
            // human name (nameComponents are withheld from share.participants
            // — discoverability is gone). Capture it now for the roster.
            Self.storeOwnerName(from: metadata)
        } catch {
            AppLogger.error("Failed to accept household share invite: \(error.localizedDescription)", category: "cloud.sharing")
            lastError = error.localizedDescription
            return
        }
        HouseholdSyncEngine.shared.start()
        // start() is a no-op when the engines already exist (normal case —
        // they're created at app launch), and no push is guaranteed for a
        // zone that was shared BEFORE we became a participant. Without an
        // explicit fetch here, the new member's library stays empty until
        // the app happens to background-cycle.
        await HouseholdSyncEngine.shared.fetchChanges()
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
        // No cachedShare fast path here: the share sheet mutates the share
        // (add/remove participants, stop sharing), and CloudKit rejects those
        // saves with a silent conflict if the instance carries a stale change
        // tag. Always hand the sheet a fresh server copy — `refresh()` may
        // have cached this share long before the sheet opens. (This is also
        // what guarantees ensureShareBranding actually runs.)

        // Fix 6: dual-role guard. If this device is already a MEMBER of
        // someone else's household (found via the shared database),
        // creating our own zone-wide share here would give one device two
        // roles — and a later raced `refresh()` (owner-lookup finding the
        // share we're about to create, member-lookup finding the one we
        // guarded against) could wipe the shared-in cache out from under it.
        if try await fetchExistingSharedZoneShare() != nil {
            let error = HouseholdError.alreadyInHousehold
            lastError = error.errorDescription
            AppLogger.error("makeZoneShare: device is already a household member, refusing to create a second share", category: "cloud.sharing")
            throw error
        }

        try await ensureHouseholdZoneExists()

        if let share = try await fetchExistingZoneShare() {
            let branded = await ensureShareBranding(share)
            cachedShare = branded
            isHouseholdOwner = true
            members = Self.members(from: branded)
            return (branded, container)
        }

        let share = CKShare(recordZoneID: HouseholdSchema.ownerZoneID)
        brandShare(share)
        share.publicPermission = .none

        // Fix 5: `modifyRecords(saving:deleting:)` returns per-record
        // Results that do NOT throw on a failed save — the call above only
        // throws for request-level failures (network, auth). Without
        // checking the per-record result, a rejected share save (e.g. a
        // conflicting share already exists server-side) looked identical to
        // success: `cachedShare` got set to our local, unsaved `CKShare`
        // instance and the caller happily presented a share sheet for a
        // share CloudKit never actually created.
        let modifyResult = try await privateDB.modifyRecords(saving: [share], deleting: [])
        guard let saveResult = modifyResult.saveResults[share.recordID] else {
            let error = HouseholdError.missingShareSaveResult
            lastError = error.errorDescription
            AppLogger.error("makeZoneShare: CloudKit returned no save result for the share record", category: "cloud.sharing")
            throw error
        }
        let savedRecord: CKRecord
        do {
            savedRecord = try saveResult.get()
        } catch {
            lastError = error.localizedDescription
            AppLogger.error("makeZoneShare: failed to save zone-wide share: \(error.localizedDescription)", category: "cloud.sharing")
            throw error
        }
        guard let savedShare = savedRecord as? CKShare else {
            let error = HouseholdError.unexpectedShareRecordType
            lastError = error.errorDescription
            AppLogger.error("makeZoneShare: saved share record was not a CKShare", category: "cloud.sharing")
            throw error
        }

        // Use the RETURNED server share (carries the real change tag), not
        // the local `share` instance we constructed above.
        cachedShare = savedShare
        isHouseholdOwner = true
        members = Self.members(from: savedShare)

        await migrateDecoyShareIfNeeded()

        // Fix 9: seed the zone-resident settings record from day one, so a
        // second owner device (or this same device after a relaunch) never
        // has to guess the policy from an empty cache.
        HouseholdSyncEngine.shared.mirrorSettings(shareWholeLibrary: HouseholdMirrorCoordinator.localShareWholeLibraryDefault())

        return (savedShare, container)
    }

    // MARK: - Share branding

    /// What the invite renders as on the receiving device. Without a type and
    /// thumbnail, iOS shows the anonymous "wants to collaborate" bubble with a
    /// generic document glyph — nothing says PaperTrail.
    static let shareTitle = "PaperTrail Household"
    private static let shareTypeIdentifier = "nikhilsh.PaperTrail.household"

    // MARK: - Owner display name

    /// CloudKit stopped exposing participant `nameComponents` (user
    /// discoverability is gone), so a member's roster shows the owner as a
    /// bare "Owner" placeholder. Two recovery paths, in priority order:
    /// 1. A custom field on the CKShare, written from the owner's typed
    ///    display name (Household screen) — works retroactively for shares
    ///    accepted before this shipped.
    /// 2. The owner identity captured from the invite metadata at accept
    ///    time (`storeOwnerName(from:)`), the one moment iOS provides it.
    static let ownerDisplayNameShareKey = "ownerDisplayName"
    static let ownerDisplayNameDefaultsKey = "household.ownerDisplayName"
    static let acceptedOwnerNameDefaultsKey = "household.acceptedOwnerName"

    private static func storeOwnerName(from metadata: CKShare.Metadata) {
        let identity = metadata.ownerIdentity
        let formatted = identity.nameComponents.map {
            PersonNameComponentsFormatter().string(from: $0)
        } ?? ""
        let name = !formatted.isEmpty
            ? formatted
            : (identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber ?? "")
        guard !name.isEmpty else {
            AppLogger.info("Share accept metadata carried no owner name", category: "cloud.sharing")
            return
        }
        UserDefaults.standard.set(name, forKey: acceptedOwnerNameDefaultsKey)
        AppLogger.info("Captured owner name from share accept metadata", category: "cloud.sharing")
    }

    private static func storedOwnerName(share: CKShare) -> String? {
        if let fromShare = share[ownerDisplayNameShareKey] as? String, !fromShare.isEmpty {
            return fromShare
        }
        if let fromInvite = UserDefaults.standard.string(forKey: acceptedOwnerNameDefaultsKey),
           !fromInvite.isEmpty {
            return fromInvite
        }
        return nil
    }

    /// Persist the owner's typed display name and push it onto the live
    /// share so members' rosters pick it up on their next refresh.
    /// Best-effort: a failed save is logged, never surfaced as an error.
    func updateOwnerDisplayName(_ name: String) async {
        guard isHouseholdOwner else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: Self.ownerDisplayNameDefaultsKey)
        guard !trimmed.isEmpty else { return }
        do {
            guard let share = try await fetchExistingShare() else { return }
            share[Self.ownerDisplayNameShareKey] = trimmed as CKRecordValue
            _ = try await privateDB.modifyRecords(saving: [share], deleting: [])
            AppLogger.info("Owner display name pushed to household share", category: "cloud.sharing")
        } catch {
            AppLogger.error("Failed to push owner display name: \(error.localizedDescription)", category: "cloud.sharing")
        }
    }

    private func brandShare(_ share: CKShare) {
        share[CKShare.SystemFieldKey.title] = Self.shareTitle as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = Self.shareTypeIdentifier as CKRecordValue
        if let thumbnail = Self.shareThumbnailData() {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumbnail as CKRecordValue
        }
        if let ownerName = UserDefaults.standard.string(forKey: Self.ownerDisplayNameDefaultsKey),
           !ownerName.isEmpty {
            share[Self.ownerDisplayNameShareKey] = ownerName as CKRecordValue
        }
    }

    /// Upgrade an already-saved share to the current branding. Best-effort:
    /// a failed save is logged and the original share returned — branding must
    /// never block presenting the invite sheet.
    private func ensureShareBranding(_ share: CKShare) async -> CKShare {
        let title = share[CKShare.SystemFieldKey.title] as? String
        let type = share[CKShare.SystemFieldKey.shareType] as? String
        let hasThumbnail = share[CKShare.SystemFieldKey.thumbnailImageData] != nil
        let wantedOwnerName = UserDefaults.standard.string(forKey: Self.ownerDisplayNameDefaultsKey)
        let ownerNameStale = (wantedOwnerName?.isEmpty == false)
            && (share[Self.ownerDisplayNameShareKey] as? String) != wantedOwnerName
        guard title != Self.shareTitle || type != Self.shareTypeIdentifier || !hasThumbnail
                || ownerNameStale else {
            return share
        }
        brandShare(share)
        do {
            let result = try await privateDB.modifyRecords(saving: [share], deleting: [])
            if let saved = try result.saveResults[share.recordID]?.get() as? CKShare {
                AppLogger.info("Rebranded existing household share", category: "cloud.sharing")
                return saved
            }
            AppLogger.error("Rebranding household share returned no save result", category: "cloud.sharing")
        } catch {
            AppLogger.error("Failed to rebrand household share: \(error.localizedDescription)", category: "cloud.sharing")
        }
        return share
    }

    /// The app icon, downscaled for the CKShare thumbnail. Resolved through
    /// `CFBundleIcons` because asset-catalog app icons aren't directly loadable
    /// by the catalog name.
    static func shareThumbnailData() -> Data? {
        guard let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last,
              let icon = UIImage(named: name) else { return nil }
        let side: CGFloat = 120
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let scaled = renderer.image { _ in
            icon.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return scaled.pngData()
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
            // Fix 5: check per-record delete results (log-accurate) — still
            // non-fatal either way, this function never throws.
            let modifyResult = try await privateDB.modifyRecords(saving: [], deleting: toDelete)
            let failures = modifyResult.deleteResults.compactMapValues { result -> Error? in
                if case .failure(let error) = result { return error }
                return nil
            }
            if failures.isEmpty {
                AppLogger.info("Migrated decoy household-root record to zone-wide share", category: "cloud.sharing")
            } else {
                for (recordID, error) in failures {
                    AppLogger.error("Decoy household-root migration: failed to delete \(recordID.recordName): \(error.localizedDescription)", category: "cloud.sharing")
                }
            }
        } catch let ckError as CKError where ckError.code == .unknownItem {
            // No decoy record to migrate — nothing to do.
        } catch {
            AppLogger.error("Decoy household-root migration failed (non-fatal): \(error.localizedDescription)", category: "cloud.sharing")
        }
    }

    /// Fix 7: called from `HouseholdSyncEngine.resetLocalState()` on
    /// `.accountChange`. The previous account's cached share/roster must not
    /// survive into the new account's session — without this, `refresh()`
    /// wouldn't run again until something happened to trigger it, and until
    /// then every `hasActiveShare`/`isHouseholdOwner` check would keep
    /// answering with the OLD account's state.
    func resetForAccountChange() {
        cachedShare = nil
        members = []
        isHouseholdOwner = true
    }

    private static func members(from share: CKShare) -> [HouseholdMember] {
        // "You" is the LOCAL participant, not the owner — on a member's
        // device the owner is somebody else, and labeling them "You" made
        // Vanessa's roster read "You (Owner) + Vanessa Ho".
        let currentUserRecordName = share.currentUserParticipant?.userIdentity.userRecordID?.recordName
        return share.participants.compactMap { participant in
            let identity = participant.userIdentity
            let email = identity.lookupInfo?.emailAddress
            let isCurrentUser = currentUserRecordName != nil
                && identity.userRecordID?.recordName == currentUserRecordName
            // iCloud usually withholds nameComponents until the invitee
            // accepts (and sometimes after) — fall back to the email or phone
            // the invite was addressed to before giving up on a placeholder.
            let formatted = identity.nameComponents.map {
                PersonNameComponentsFormatter().string(from: $0)
            } ?? ""
            let name: String
            if isCurrentUser {
                name = "You"
            } else if !formatted.isEmpty {
                name = formatted
            } else if let email {
                name = email
            } else if let phone = identity.lookupInfo?.phoneNumber {
                name = phone
            } else if participant.role == .owner, let ownerName = storedOwnerName(share: share) {
                // Owner participants never carry lookupInfo (they created the
                // share, nobody "invited" them) — fall back to the name the
                // owner typed (share field) or the invite metadata capture.
                name = ownerName
            } else {
                name = participant.role == .owner ? "Owner" : "Member"
            }
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
