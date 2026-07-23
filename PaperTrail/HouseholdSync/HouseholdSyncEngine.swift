import CloudKit
import Foundation
import SwiftData

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

    /// Last-known server `CKRecord` per record name — updated on fetch, on
    /// confirmed save, and from `.serverRecordChanged` conflict errors.
    /// Outgoing updates MUST be applied onto one of these (it carries the
    /// server change tag); sending a freshly-constructed `CKRecord` for an
    /// existing record would conflict forever. In-memory only: after a
    /// relaunch the first update of a record conflicts once, we capture the
    /// server record from the error, and the retry succeeds.
    private var serverRecords: [String: CKRecord] = [:]

    /// Record names for which a failed delete has already been re-queued
    /// once this launch (Fix 2 — `failedRecordDeletes` handling). Guards
    /// against a tight retry loop if the delete keeps failing; after one
    /// retry we just error-log.
    private var retriedDeletes: Set<String> = []

    // .shared, not a fresh HouseholdCache() — the previous default was a
    // private instance no view could ever observe (latent bug fixed in Phase
    // 3; see HouseholdCache's doc comment). Tests keep injecting their own
    // temp-directory cache via this same parameter.
    init(cache: HouseholdCache = .shared) {
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
            let message = "Private household sync engine fetchChanges failed: \(error.localizedDescription)"
            if error.isTransientNetworkError { AppLogger.warn(message, category: "cloud.sharing") }
            else { AppLogger.error(message, category: "cloud.sharing") }
        }
        do {
            try await sharedEngine?.fetchChanges()
        } catch {
            let message = "Shared household sync engine fetchChanges failed: \(error.localizedDescription)"
            if error.isTransientNetworkError { AppLogger.warn(message, category: "cloud.sharing") }
            else { AppLogger.error(message, category: "cloud.sharing") }
        }
    }

    // MARK: - Outbound mirroring
    //
    // Fix 2: no pending-DTO maps. `CKSyncEngine.state` already durably
    // persists which record IDs are pending across a relaunch; these
    // functions only need to queue the record ID. The DTO content itself is
    // rebuilt from SwiftData ON DEMAND in `pendingRecord(for:)` when the
    // engine actually asks for it (`nextRecordZoneChangeBatch`) — so a
    // relaunch between "queue" and "send" can never drop the write, and a
    // late v1 confirmation can never clobber an already-queued v2 (there's
    // no stale DTO sitting in a map to be cleared out from under it).

    /// Queue a purchase-record mirror write to `HouseholdZone`.
    func mirror(dto: SharedPurchaseRecordDTO) {
        guard HouseholdManager.recordSharingEnabled else { return }
        guard let privateEngine else { return }
        let recordID = CKRecord.ID(recordName: HouseholdSchema.RecordName.purchaseRecord(dto.id), zoneID: HouseholdSchema.ownerZoneID)
        privateEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        AppLogger.info("Queued mirror write for purchase record \(dto.id)", category: "cloud.sharing")
    }

    /// Queue an attachment mirror write to `HouseholdZone`.
    func mirror(dto: SharedAttachmentDTO) {
        guard HouseholdManager.recordSharingEnabled else { return }
        guard let privateEngine else { return }
        let recordID = CKRecord.ID(recordName: HouseholdSchema.RecordName.attachment(dto.id), zoneID: HouseholdSchema.ownerZoneID)
        privateEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        AppLogger.info("Queued mirror write for attachment \(dto.id)", category: "cloud.sharing")
    }

    /// Queue a write of the zone-resident `HouseholdSettings` record (Fix 9
    /// — see docs/SHARING_ARCHITECTURE.md). Not DTO-backed: the record's
    /// content is read straight from `UserDefaults`, via
    /// `HouseholdMirrorCoordinator.localShareWholeLibraryDefault()`, at send
    /// time in `pendingRecord(for:)` — always current, same durability
    /// story as the DTO-backed mirrors above. `shareWholeLibrary` here is
    /// only for the log line; the actual value sent is whatever's current
    /// in `UserDefaults` when the engine gets around to sending it.
    func mirrorSettings(shareWholeLibrary: Bool) {
        guard HouseholdManager.recordSharingEnabled else { return }
        guard let privateEngine else { return }
        let recordID = CKRecord.ID(recordName: HouseholdSchema.RecordName.settings, zoneID: HouseholdSchema.ownerZoneID)
        privateEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        AppLogger.info("Queued mirror write for household settings (shareWholeLibrary=\(shareWholeLibrary))", category: "cloud.sharing")
    }

    /// Queue removal of a mirrored purchase record (unshare / delete from
    /// `HouseholdZone`).
    func unshare(id: UUID) {
        guard HouseholdManager.recordSharingEnabled else { return }
        guard let privateEngine else { return }
        let recordID = CKRecord.ID(recordName: HouseholdSchema.RecordName.purchaseRecord(id), zoneID: HouseholdSchema.ownerZoneID)
        privateEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        AppLogger.info("Queued unshare for purchase record \(id)", category: "cloud.sharing")
    }

    /// Queue removal of a mirrored attachment (unshare / delete from
    /// `HouseholdZone`) — same shape as `unshare(id:)` above.
    func unshareAttachment(id: UUID) {
        guard HouseholdManager.recordSharingEnabled else { return }
        guard let privateEngine else { return }
        let recordID = CKRecord.ID(recordName: HouseholdSchema.RecordName.attachment(id), zoneID: HouseholdSchema.ownerZoneID)
        privateEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        AppLogger.info("Queued unshare for attachment \(id)", category: "cloud.sharing")
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
                storeSharedImageIfNeeded(dto: dto, record: record)
            }
        case HouseholdSchema.RecordType.settings:
            // Fix 9: the zone-resident settings record is authoritative once
            // it's arrived — see HouseholdMirrorCoordinator.effectiveShareWholeLibrary().
            if let value = record[HouseholdSchema.SettingsField.shareWholeLibrary.rawValue] as? Int64 {
                cache.setShareWholeLibrarySetting(value != 0)
                AppLogger.info("Fetched household settings: shareWholeLibrary=\(value != 0)", category: "cloud.sharing")
            } else {
                AppLogger.error("Malformed HouseholdSettings: missing/invalid shareWholeLibrary field", category: "cloud.sharing")
            }
        default:
            AppLogger.warn("Fetched unknown record type \(record.recordType)", category: "cloud.sharing")
        }
    }

    /// After upserting a fetched `SharedAttachment`, pull down its image
    /// asset (if the record carries one) into `HouseholdCache`'s images
    /// directory — UNLESS this device already has the original file at
    /// `Documents/Attachments/<localFilename>`. That skip matters on the
    /// owner's own device(s): the owner's private engine fetches back the
    /// records it just mirrored, and without this check every one of its own
    /// attachment images would get duplicated into the cache dir on every
    /// fetch.
    private func storeSharedImageIfNeeded(dto: SharedAttachmentDTO, record: CKRecord) {
        guard let asset = record[HouseholdSchema.AttachmentField.asset.rawValue] as? CKAsset,
              let assetFileURL = asset.fileURL else { return }
        let originalURL = ImageStorageManager.url(for: dto.localFilename)
        if FileManager.default.fileExists(atPath: originalURL.path) {
            AppLogger.info("Skipped shared image, original present for attachment \(dto.id)", category: "cloud.sharing")
            return
        }
        cache.storeImage(from: assetFileURL, attachmentID: dto.id)
        AppLogger.info("Stored shared image for attachment \(dto.id)", category: "cloud.sharing")
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
    /// for v1. `syncEngine` is the ORIGINATING engine from the event (not
    /// necessarily `privateEngine` — Fix 2: re-queuing onto the wrong engine
    /// silently never sends).
    private func handleFailedRecordSave(record: CKRecord, error: CKError, syncEngine: CKSyncEngine) {
        if error.code == .serverRecordChanged {
            guard let serverRecord = error.serverRecord else {
                // No server record on the error means there's nothing safe to
                // re-apply our edit onto — re-queuing here would just conflict
                // again in a tight loop. Log and stop; the next reconcile
                // picks this record back up if it's still supposed to mirror.
                AppLogger.error(
                    "serverRecordChanged for \(record.recordID.recordName) but error carried no server record; not re-queuing",
                    category: "cloud.sharing"
                )
                return
            }
            AppLogger.warn(
                "Server record changed for \(record.recordID.recordName), re-queuing local edit onto server record",
                category: "cloud.sharing"
            )
            serverRecords[record.recordID.recordName] = serverRecord
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        } else {
            AppLogger.error(
                "Failed to send record \(record.recordID.recordName): \(error.localizedDescription)",
                category: "cloud.sharing"
            )
            // Terminal (non-conflict) failure: roll back the optimistic cache
            // entry so this looks unmirrored again and a later reconcile
            // retries it, rather than the cache silently believing a write
            // succeeded that never did.
            if let id = Self.uuid(fromRecordName: record.recordID.recordName, prefix: "rec-") {
                cache.removePurchaseRecord(id: id)
            } else if let id = Self.uuid(fromRecordName: record.recordID.recordName, prefix: "att-") {
                cache.removeAttachment(id: id)
            }
        }
    }

    /// `failedRecordDeletes` handling (Fix 2): re-queue a failed delete
    /// exactly once per record name per launch, and only when the local
    /// SwiftData record genuinely no longer exists (this was a real
    /// unshare/delete). If it DOES still exist locally, re-queuing a delete
    /// would be actively wrong — something upstream raced, not a delete that
    /// needs retrying.
    private func handleFailedRecordDelete(recordID: CKRecord.ID, error: CKError, syncEngine: CKSyncEngine) {
        AppLogger.error(
            "Failed to delete record \(recordID.recordName): \(error.localizedDescription)",
            category: "cloud.sharing"
        )
        guard !retriedDeletes.contains(recordID.recordName) else {
            AppLogger.error(
                "Delete for \(recordID.recordName) already retried once this launch, not retrying again",
                category: "cloud.sharing"
            )
            return
        }
        guard !localRecordStillExists(recordID: recordID) else { return }
        retriedDeletes.insert(recordID.recordName)
        syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        AppLogger.warn("Re-queuing failed delete for \(recordID.recordName) (retry 1/1)", category: "cloud.sharing")
    }

    /// Used by `handleFailedRecordDelete` to distinguish "this delete was a
    /// real unshare, safe to retry" from "something is confused, do not
    /// retry." `@MainActor` — `PaperTrailModelContainer.shared.mainContext`
    /// must be touched on the main actor, matching every other SwiftData
    /// access in this pipeline (`HouseholdMirrorCoordinator.reconcile()`,
    /// `.share(recordID:)`).
    private func localRecordStillExists(recordID: CKRecord.ID) -> Bool {
        let context = PaperTrailModelContainer.shared.mainContext
        if let id = Self.uuid(fromRecordName: recordID.recordName, prefix: "rec-") {
            let matches = (try? context.fetch(FetchDescriptor<PurchaseRecord>(predicate: #Predicate { $0.id == id }))) ?? []
            return !matches.isEmpty
        }
        if let id = Self.uuid(fromRecordName: recordID.recordName, prefix: "att-") {
            let matches = (try? context.fetch(FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id }))) ?? []
            return !matches.isEmpty
        }
        return false
    }

    /// Full teardown on `.accountChange` (Fix 7). The stale engines'
    /// serialization is scoped to the OLD account; simply clearing the cache
    /// and state files left the in-memory `CKSyncEngine` objects alive, and
    /// their very next `.stateUpdate` would write the old account's
    /// serialization right back to disk. Discard both engines; the caller
    /// reschedules `start()` outside the delegate callback so the new account
    /// gets fresh, unserialized engines. Only ever called for
    /// signOut/switchAccounts — a first-start `.signIn` must NOT reset (see
    /// the accountChange handler).
    private func resetLocalState() {
        serverRecords.removeAll()
        retriedDeletes.removeAll()
        cache.removeAll()
        cache.setStateData(nil, for: .privateDB)
        cache.setStateData(nil, for: .sharedDB)
        privateEngine = nil
        sharedEngine = nil
        HouseholdManager.shared.resetForAccountChange()
        // Deliberately no start() here: this runs inside a CKSyncEngine
        // delegate event, and CKSyncEngine.init blocks on an internal queue
        // that's busy delivering that event. The caller schedules the restart
        // in a detached Task after the event returns.
    }

    private static func uuid(fromRecordName recordName: String, prefix: String) -> UUID? {
        guard recordName.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(recordName.dropFirst(prefix.count)))
    }

    /// Rebuilds the outgoing `CKRecord` for `recordID` FROM SWIFTDATA, at
    /// send time (Fix 2 — see docs/SHARING_ARCHITECTURE.md). Called from
    /// `nextRecordZoneChangeBatch`'s `recordProvider` closure, which may run
    /// off `MainActor` if `CKSyncEngine.RecordZoneChangeBatch` marks it
    /// `@Sendable` — kept as a real `await`-able method (rather than inline
    /// property access in the closure) so the actor hop back onto `MainActor`
    /// is explicit and correct either way.
    ///
    /// Returns `nil` when the local record has since been deleted (the
    /// deletion hook already queued a `.deleteRecord` for it — see
    /// `HouseholdMirrorCoordinator.recordDeleted`), so there's nothing to
    /// send for this now-stale `.saveRecord` pending change.
    private func pendingRecord(for recordID: CKRecord.ID) -> CKRecord? {
        if recordID.recordName == HouseholdSchema.RecordName.settings {
            return pendingSettingsRecord(recordID: recordID)
        }
        if let id = Self.uuid(fromRecordName: recordID.recordName, prefix: "rec-") {
            return pendingPurchaseRecord(id: id, recordID: recordID)
        }
        if let id = Self.uuid(fromRecordName: recordID.recordName, prefix: "att-") {
            return pendingAttachmentRecord(id: id, recordID: recordID)
        }
        return nil
    }

    private func pendingPurchaseRecord(id: UUID, recordID: CKRecord.ID) -> CKRecord? {
        let context = PaperTrailModelContainer.shared.mainContext
        guard let record = try? context.fetch(
            FetchDescriptor<PurchaseRecord>(predicate: #Predicate { $0.id == id })
        ).first else {
            return nil
        }
        let dto = SharedPurchaseRecordDTO(record: record)
        if let base = serverRecords[recordID.recordName] {
            SharedRecordMapper.apply(dto, to: base)
            return base
        }
        return SharedRecordMapper.makeCKRecord(from: dto, zoneID: recordID.zoneID)
    }

    private func pendingAttachmentRecord(id: UUID, recordID: CKRecord.ID) -> CKRecord? {
        let context = PaperTrailModelContainer.shared.mainContext
        guard let attachment = try? context.fetch(
            FetchDescriptor<Attachment>(predicate: #Predicate { $0.id == id })
        ).first else {
            return nil
        }
        let dto = SharedAttachmentDTO(attachment: attachment)
        // Only pass a file URL through if the image is actually on disk —
        // SharedRecordMapper.apply(_:to:assetFileURL:) treats `nil` as
        // "leave the existing asset alone", not "clear it".
        let localImageURL = ImageStorageManager.url(for: dto.localFilename)
        let assetFileURL = FileManager.default.fileExists(atPath: localImageURL.path) ? localImageURL : nil
        if let base = serverRecords[recordID.recordName] {
            SharedRecordMapper.apply(dto, to: base, assetFileURL: assetFileURL)
            return base
        }
        return SharedRecordMapper.makeCKRecord(from: dto, zoneID: recordID.zoneID, assetFileURL: assetFileURL)
    }

    /// Builds/updates the zone-resident `HouseholdSettings` record from
    /// `UserDefaults`'s current value — see `mirrorSettings(shareWholeLibrary:)`.
    private func pendingSettingsRecord(recordID: CKRecord.ID) -> CKRecord {
        let value = HouseholdMirrorCoordinator.localShareWholeLibraryDefault()
        let record = serverRecords[recordID.recordName]
            ?? CKRecord(recordType: HouseholdSchema.RecordType.settings, recordID: recordID)
        record[HouseholdSchema.SettingsField.shareWholeLibrary.rawValue] = Int64(value ? 1 : 0) as CKRecordValue
        return record
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
            switch accountChange.changeType {
            case .signIn:
                // A fresh engine (nil stateSerialization) reports the current
                // user as .signIn on its very first start. There is no previous
                // account's data to purge — and resetting here recreated the
                // engines with nil state, which re-emitted .signIn: an infinite
                // engine-rebuild loop that hung the main thread (CKSyncEngine's
                // init blocks on an internal queue that is busy delivering this
                // very event) and grew memory until the watchdog killed the app
                // (Sentry APPLE-IOS-8/9, build 25).
                AppLogger.info("CloudKit account signed in — no reset needed", category: "cloud.sharing")
            default:
                // signOut / switchAccounts: purge this account's local sync
                // state, then rebuild the engines OUTSIDE this delegate
                // callback — creating a CKSyncEngine synchronously from inside
                // handleEvent deadlocks (see above).
                AppLogger.warn("CloudKit account changed (\(String(describing: accountChange.changeType))), resetting local sync state", category: "cloud.sharing")
                resetLocalState()
                Task { @MainActor [weak self] in
                    self?.start()
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            cache.withBatchedSaves {
                for modification in changes.modifications {
                    applyFetchedModification(modification.record)
                }
                for deletion in changes.deletions {
                    applyFetchedDeletion(recordID: deletion.recordID, recordType: deletion.recordType)
                }
            }
            AppLogger.info(
                "Applied \(changes.modifications.count) fetched change(s), \(changes.deletions.count) deletion(s)",
                category: "cloud.sharing"
            )

        case .fetchedDatabaseChanges(let changes):
            // Fix 3: the private database also contains SwiftData's own
            // com.apple.coredata.cloudkit.zone — a deletion notification for
            // THAT zone (or any other unrelated zone) must never purge this
            // cache. Only a deletion of HouseholdZone itself is real
            // evidence the household share ended.
            for deletion in changes.deletions {
                if deletion.zoneID.zoneName == HouseholdSchema.zoneName {
                    AppLogger.warn(
                        "HouseholdZone deleted upstream, purging local cache",
                        category: "cloud.sharing"
                    )
                    cache.removeAll()
                } else {
                    AppLogger.info(
                        "Ignoring unrelated zone deletion: \(deletion.zoneID.zoneName) (reason: \(String(describing: deletion.reason)))",
                        category: "cloud.sharing"
                    )
                }
            }

        case .sentDatabaseChanges(let changes):
            // Zone-creation failures (`ensureZone()`) are otherwise invisible
            // — nothing downstream surfaces "the zone never got created", it
            // just looks like sync silently does nothing.
            for failure in changes.failedZoneSaves {
                AppLogger.error(
                    "Failed to save zone \(failure.zone.zoneID.zoneName): \(failure.error.localizedDescription)",
                    category: "cloud.sharing"
                )
            }
            for (zoneID, error) in changes.failedZoneDeletes {
                AppLogger.error(
                    "Failed to delete zone \(zoneID.zoneName): \(error.localizedDescription)",
                    category: "cloud.sharing"
                )
            }

        case .sentRecordZoneChanges(let changes):
            for failure in changes.failedRecordSaves {
                handleFailedRecordSave(record: failure.record, error: failure.error, syncEngine: syncEngine)
            }
            for (recordID, error) in changes.failedRecordDeletes {
                handleFailedRecordDelete(recordID: recordID, error: error, syncEngine: syncEngine)
            }
            for recordID in changes.deletedRecordIDs {
                serverRecords.removeValue(forKey: recordID.recordName)
                retriedDeletes.remove(recordID.recordName)
            }
            // Fix 2: confirmation-time truth. The saved server record is now
            // definitely what CloudKit has, so parse it back into a DTO and
            // upsert into the cache here — rather than trusting an earlier
            // optimistic write that a later, still-pending edit might have
            // since superseded.
            cache.withBatchedSaves {
                for saved in changes.savedRecords {
                    serverRecords[saved.recordID.recordName] = saved
                    switch saved.recordType {
                    case HouseholdSchema.RecordType.purchaseRecord:
                        if let dto = SharedRecordMapper.makePurchaseDTO(from: saved) {
                            cache.upsert(dto)
                        }
                    case HouseholdSchema.RecordType.attachment:
                        if let dto = SharedRecordMapper.makeAttachmentDTO(from: saved) {
                            cache.upsert(dto)
                        }
                    default:
                        break
                    }
                }
            }
            if !changes.savedRecords.isEmpty {
                AppLogger.info("Sent \(changes.savedRecords.count) record change(s)", category: "cloud.sharing")
            }

        default:
            AppLogger.info("Unhandled CKSyncEngine event: \(event)", category: "cloud.sharing")
        }
    }

    /// Fix 4: scope the private engine's fetches to `HouseholdZone`. The
    /// private database also contains SwiftData's own
    /// `com.apple.coredata.cloudkit.zone` — without this, the private
    /// engine's first fetch would download the entire CD_* SwiftData mirror
    /// into this engine's change-tracking state. The shared engine only ever
    /// sees zones explicitly shared to us, so it's safe to fetch everything.
    func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        if syncEngine === privateEngine {
            return CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([HouseholdSchema.ownerZoneID]))
        }
        return CKSyncEngine.FetchChangesOptions(scope: .all)
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { [weak self] recordID in
            guard let record = await self?.pendingRecord(for: recordID) else {
                // Helps diagnose a stuck queue on-device: CKSyncEngine thinks
                // this record is pending but we have no DTO for it (e.g. it
                // was unshared/cleared between being queued and being sent).
                await AppLogger.info(
                    "No pending DTO for \(recordID.recordName) in nextRecordZoneChangeBatch",
                    category: "cloud.sharing"
                )
                return nil
            }
            return record
        }
    }
}
