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

    @ObservationIgnored private lazy var container = CKContainer(identifier: containerID)
    @ObservationIgnored private var cachedShare: CKShare?

    private init() {}

    private var privateDB: CKDatabase { container.privateCloudDatabase }

    /// Load the existing household share (if any) and publish its participants.
    func refresh() async {
        do {
            if let share = try await fetchExistingShare() {
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
        if let share = cachedShare ?? (try await fetchExistingShare()) {
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
