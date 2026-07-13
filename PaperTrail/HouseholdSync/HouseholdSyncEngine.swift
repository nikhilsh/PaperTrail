import CloudKit
import Foundation

/// Owns the two `CKSyncEngine` instances (iOS 17+) that carry
/// household-shared records between the owner's private database and
/// members' shared database (Milestone 4 Phase 1 — see
/// docs/SHARING_ARCHITECTURE.md). Nothing here runs unless
/// `HouseholdManager.recordSharingEnabled` is `true`; no app code calls into
/// this class yet — it is flag-guarded, inert scaffolding.
///
/// Concurrency: `@MainActor`, matching `CloudImageSyncManager` and
/// `HouseholdManager` (the project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so this is also the ambient
/// default — the annotation is kept explicit for clarity). `CKSyncEngineDelegate`
/// methods are `async`, so the system can call them from any context and the
/// implicit actor hop back onto `MainActor` happens for free; no `nonisolated`
/// + manual `Task { @MainActor in }` hopping needed.
@MainActor
final class HouseholdSyncEngine {

    static let shared = HouseholdSyncEngine()

    /// Which of the two `CKSyncEngine`s an event/state update belongs to.
    enum EngineKind: String, Sendable {
        case privateDB
        case sharedDB
    }

    private let containerID = "iCloud.nikhilsh.PaperTrail"

    private lazy var container = CKContainer(identifier: containerID)
    private let cache: HouseholdCache

    private var privateEngine: CKSyncEngine?
    private var sharedEngine: CKSyncEngine?

    /// Pending outgoing DTOs keyed by `CKRecord.ID.recordName`, consulted by
    /// `nextRecordZoneChangeBatch` when the engine asks for record content to
    /// send. Populated by `mirror(dto:)`, drained on confirmed send.
    private var pendingPurchaseRecords: [String: SharedPurchaseRecordDTO] = [:]
    private var pendingAttachments: [String: SharedAttachmentDTO] = [:]

    /// Last-known server `CKRecord` per record name — updated on fetch, on
    /// confirmed save, and from `.serverRecordChanged` conflict errors.
    /// Outgoing updates MUST be applied onto one of these (it carries the
    /// server change tag); sending a freshly-constructed `CKRecord` for an
    /// existing record would conflict forever. In-memory only: after a
    /// relaunch the first update of a record conflicts once, we capture the
    /// server record from the error, and the retry succeeds.
    private var serverRecords: [String: CKRecord] = [:]

    init(cache: HouseholdCache = HouseholdCache()) {
        self.cache = cache
    }

    // MARK: - Lifecycle

    /// Start both engines (idempotent — safe to call repeatedly, e.g. on
    /// every app foreground). No-ops unless record sharing is enabled.
    func start() {
        guard HouseholdManager.recordSharingEnabled else { return }
        AppLogger.info("Starting household sync engines", category: "cloud.sharing")

        cache.load()

        if privateEngine == nil {
            let serialization = cache.stateSerialization(for: .privateDB)
            let configuration = CKSyncEngine.Configuration(
                database: container.privateCloudDatabase,
                stateSerialization: serialization,
                delegate: self
            )
            privateEngine = CKSyncEngine(configuration)
            AppLogger.info("Private household sync engine started", category: "cloud.sharing")
        }

        if sharedEngine == nil {
            let serialization = cache.stateSerialization(for: .sharedDB)
            let configuration = CKSyncEngine.Configuration(
                database: container.sharedCloudDatabase,
                stateSerialization: serialization,
                delegate: self
            )
            sharedEngine = CKSyncEngine(configuration)
            AppLogger.info("Shared household sync engine started", category: "cloud.sharing")
        }

        ensureZone()
    }

    /// Queue creation of `HouseholdZone` in the owner's private database.
    /// Safe to call repeatedly — `CKSyncEngine` coalesces duplicate pending
    /// zone saves and `.saveZone` is itself idempotent server-side.
    func ensureZone() {
        guard HouseholdManager.recordSharingEnabled else { return }
        guard let privateEngine else { return }
        let zone = CKRecordZone(zoneID: HouseholdSchema.ownerZoneID)
        privateEngine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        AppLogger.info("Queued HouseholdZone creation", category: "cloud.sharing")
    }

    /// Poll fallback: ask both engines to fetch changes now. CloudKit push
    /// notifications drive `CKSyncEngine` automatically, but pushes are
    /// best-effort, so this is additionally called on app foreground (wired
    /// in Phase 3) to close any gap. No-op unless record sharing is enabled
    /// or an engine hasn't been started yet.
    func fetchChanges() async {
        guard HouseholdManager.recordSharingEnabled else { return }
        do {
            try await privateEngine?.fetchChanges()
        } catch {
            AppLogger.error("Private household sync engine fetchChanges failed: \(error.localizedDescription)", category: "cloud.sharing")
        }
        do {
            try await sharedEngine?.fetchChanges()
        } catch {
            AppLogger.error("Shared household sync engine fetchChanges failed: \(error.localizedDescription)", category: "cloud.sharing")
        }
    }

    // MARK: - Outbound mirroring

    /// Queue a purchase-record mirror write to `HouseholdZone`.
    func mirror(dto: SharedPurchaseRecordDTO) {
        guard HouseholdManager.recordSharingEnabled else { return }
        guard let privateEngine else { return }
        let recordName = HouseholdSchema.RecordName.purchaseRecord(dto.id)
        pendingPurchaseRecords[recordName] = dto
        let recordID = CKRecord.ID(recordName: recordName, zoneID: HouseholdSchema.ownerZoneID)
        privateEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        AppLogger.info("Queued mirror write for purchase record \(dto.id)", category: "cloud.sharing")
    }

    /// Queue an attachment mirror write to `HouseholdZone`.
    func mirror(dto: SharedAttachmentDTO) {
        guard HouseholdManager.recordSharingEnabled else { return }
        guard let privateEngine else { return }
        let recordName = HouseholdSchema.RecordName.attachment(dto.id)
        pendingAttachments[recordName] = dto
        let recordID = CKRecord.ID(recordName: recordName, zoneID: HouseholdSchema.ownerZoneID)
        privateEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        AppLogger.info("Queued mirror write for attachment \(dto.id)", category: "cloud.sharing")
    }

    /// Queue removal of a mirrored purchase record (unshare / delete from
    /// `HouseholdZone`). Attachment un-mirroring follows the same shape but
    /// isn't wired to any caller yet in Phase 1.
    func unshare(id: UUID) {
        guard HouseholdManager.recordSharingEnabled else { return }
        guard let privateEngine else { return }
        let recordName = HouseholdSchema.RecordName.purchaseRecord(id)
        pendingPurchaseRecords.removeValue(forKey: recordName)
        let recordID = CKRecord.ID(recordName: recordName, zoneID: HouseholdSchema.ownerZoneID)
        privateEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        AppLogger.info("Queued unshare for purchase record \(id)", category: "cloud.sharing")
    }

    // MARK: - Event handling helpers

    private func engineKind(for syncEngine: CKSyncEngine) -> EngineKind {
        syncEngine === privateEngine ? .privateDB : .sharedDB
    }

    /// Apply one record CKRecord fetched from `HouseholdZone` into the cache.
    /// Factored out (rather than typed as a helper taking the whole event) so
    /// nothing here depends on spelling out `CKSyncEngine`'s nested event
    /// struct type names — see the uncertainty note on `handleEvent` below.
    private func applyFetchedModification(_ record: CKRecord) {
        serverRecords[record.recordID.recordName] = record
        switch record.recordType {
        case HouseholdSchema.RecordType.purchaseRecord:
            if let dto = SharedRecordMapper.makePurchaseDTO(from: record) {
                cache.upsert(dto)
            }
        case HouseholdSchema.RecordType.attachment:
            if let dto = SharedRecordMapper.makeAttachmentDTO(from: record) {
                cache.upsert(dto)
            }
        default:
            AppLogger.warn("Fetched unknown record type \(record.recordType)", category: "cloud.sharing")
        }
    }

    private func applyFetchedDeletion(recordID: CKRecord.ID, recordType: CKRecord.RecordType) {
        switch recordType {
        case HouseholdSchema.RecordType.purchaseRecord:
            if let id = Self.uuid(fromRecordName: recordID.recordName, prefix: "rec-") {
                cache.removePurchaseRecord(id: id)
            }
        case HouseholdSchema.RecordType.attachment:
            if let id = Self.uuid(fromRecordName: recordID.recordName, prefix: "att-") {
                cache.removeAttachment(id: id)
            }
        default:
            break
        }
    }

    /// v1 conflict strategy (design doc): server wins, then re-apply the
    /// still-pending local edit on top of it. The error carries the current
    /// server record — keep it so `pendingRecord(for:)` applies our local DTO
    /// onto it (fresh change tag) instead of resending a tagless record that
    /// would conflict again. Field-level merge is deliberately out of scope
    /// for v1.
    private func handleFailedRecordSave(record: CKRecord, error: CKError) {
        if error.code == .serverRecordChanged {
            AppLogger.warn(
                "Server record changed for \(record.recordID.recordName), re-queuing local edit onto server record",
                category: "cloud.sharing"
            )
            if let serverRecord = error.serverRecord {
                serverRecords[record.recordID.recordName] = serverRecord
            }
            privateEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        } else {
            AppLogger.error(
                "Failed to send record \(record.recordID.recordName): \(error.localizedDescription)",
                category: "cloud.sharing"
            )
        }
    }

    /// Drop a record from the outbound-DTO cache once `CKSyncEngine` confirms
    /// it's no longer pending (sent successfully or deleted server-side).
    private func clearPending(recordID: CKRecord.ID) {
        pendingPurchaseRecords.removeValue(forKey: recordID.recordName)
        pendingAttachments.removeValue(forKey: recordID.recordName)
    }

    private func resetLocalState() {
        pendingPurchaseRecords.removeAll()
        pendingAttachments.removeAll()
        serverRecords.removeAll()
        cache.removeAll()
        cache.setStateData(nil, for: .privateDB)
        cache.setStateData(nil, for: .sharedDB)
    }

    private static func uuid(fromRecordName recordName: String, prefix: String) -> UUID? {
        guard recordName.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(recordName.dropFirst(prefix.count)))
    }

    /// Looks up the pending outgoing `CKRecord` for a record ID. Called from
    /// `nextRecordZoneChangeBatch`'s `recordProvider` closure, which may run
    /// off `MainActor` if `CKSyncEngine.RecordZoneChangeBatch` marks it
    /// `@Sendable` — kept as a real `await`-able method (rather than inline
    /// property access in the closure) so the actor hop back onto `MainActor`
    /// is explicit and correct either way.
    private func pendingRecord(for recordID: CKRecord.ID) -> CKRecord? {
        if let dto = pendingPurchaseRecords[recordID.recordName] {
            if let base = serverRecords[recordID.recordName] {
                SharedRecordMapper.apply(dto, to: base)
                return base
            }
            return SharedRecordMapper.makeCKRecord(from: dto, zoneID: recordID.zoneID)
        }
        if let dto = pendingAttachments[recordID.recordName] {
            if let base = serverRecords[recordID.recordName] {
                SharedRecordMapper.apply(dto, to: base)
                return base
            }
            return SharedRecordMapper.makeCKRecord(from: dto, zoneID: recordID.zoneID)
        }
        return nil
    }
}

// MARK: - CKSyncEngineDelegate

extension HouseholdSyncEngine: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            let kind = engineKind(for: syncEngine)
            cache.setStateSerialization(stateUpdate.stateSerialization, for: kind)
            AppLogger.info("Persisted sync state for \(kind.rawValue)", category: "cloud.sharing")

        case .accountChange(let accountChange):
            AppLogger.warn("CloudKit account changed (\(String(describing: accountChange.changeType))), resetting local sync state", category: "cloud.sharing")
            resetLocalState()

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                applyFetchedModification(modification.record)
            }
            for deletion in changes.deletions {
                applyFetchedDeletion(recordID: deletion.recordID, recordType: deletion.recordType)
            }
            AppLogger.info(
                "Applied \(changes.modifications.count) fetched change(s), \(changes.deletions.count) deletion(s)",
                category: "cloud.sharing"
            )

        case .fetchedDatabaseChanges(let changes):
            if !changes.deletions.isEmpty {
                AppLogger.warn(
                    "HouseholdZone deleted upstream (\(changes.deletions.count) zone deletion(s)), purging local cache",
                    category: "cloud.sharing"
                )
                cache.removeAll()
            }

        case .sentRecordZoneChanges(let changes):
            for failure in changes.failedRecordSaves {
                handleFailedRecordSave(record: failure.record, error: failure.error)
            }
            for recordID in changes.deletedRecordIDs {
                clearPending(recordID: recordID)
                serverRecords.removeValue(forKey: recordID.recordName)
            }
            for saved in changes.savedRecords {
                clearPending(recordID: saved.recordID)
                serverRecords[saved.recordID.recordName] = saved
            }
            if !changes.savedRecords.isEmpty {
                AppLogger.info("Sent \(changes.savedRecords.count) record change(s)", category: "cloud.sharing")
            }

        default:
            AppLogger.info("Unhandled CKSyncEngine event: \(event)", category: "cloud.sharing")
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { [weak self] recordID in
            await self?.pendingRecord(for: recordID)
        }
    }
}
