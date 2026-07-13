import Foundation
import SwiftData
import UIKit

/// Reconciles the local SwiftData library against the household-sharing zone
/// (Milestone 4 Phase 3 — see docs/SHARING_ARCHITECTURE.md). Mirroring is
/// reconcile-based, not write-path-based: this listens for SwiftData saves
/// (debounced) and app foreground, diffs the local library against
/// `HouseholdCache`'s view of `HouseholdZone`, and queues mirror/unshare
/// deltas through `HouseholdSyncEngine`. Entirely flag-guarded — inert unless
/// `HouseholdManager.recordSharingEnabled` is true.
@MainActor
final class HouseholdMirrorCoordinator {

    static let shared = HouseholdMirrorCoordinator()

    /// Pure diff output — see `computeDiff`. No CloudKit/SwiftData types here
    /// so it's trivially unit-testable.
    struct Diff: Equatable {
        var recordUpserts: [SharedPurchaseRecordDTO] = []
        var recordDeletes: [UUID] = []
        var attachmentUpserts: [SharedAttachmentDTO] = []
        var attachmentDeletes: [UUID] = []
    }

    private static let shareWholeLibraryDefaultsKey = "household.shareWholeLibrary"
    private static let debounceInterval: Duration = .seconds(2)

    private var started = false
    private var debounceTask: Task<Void, Never>?
    private var didSaveObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    private init() {}

    // MARK: - Lifecycle

    /// Subscribe to SwiftData saves + app foreground. Idempotent, no-op unless
    /// record sharing is enabled.
    func start() {
        guard HouseholdManager.recordSharingEnabled else { return }
        guard !started else { return }
        started = true

        // Unscoped (object: nil): SwiftData posts `ModelContext.didSave` from
        // whichever ModelContext saved, and App Intents create ad-hoc
        // ModelContexts of their own (read-only today, but that's not an
        // assumption to bake into this notification scope).
        didSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleDebouncedReconcile()
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                await HouseholdSyncEngine.shared.fetchChanges()
                await self?.reconcile()
            }
        }

        // Initial pass: reconcile()'s owner/active-share guard reads
        // HouseholdManager.cachedShare, which is only populated by refresh() —
        // and until now refresh() only ran when the user opened HouseholdView.
        // Without this, an owner's edits after a relaunch would silently never
        // mirror until that screen was visited.
        Task { [weak self] in
            await HouseholdManager.shared.refresh()
            await self?.reconcile()
        }

        AppLogger.info("HouseholdMirrorCoordinator started", category: "cloud.sharing")
    }

    /// Cancel-and-restart a short sleep so a burst of saves (e.g. scanning
    /// several attachments in a row) coalesces into a single reconcile.
    private func scheduleDebouncedReconcile() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.reconcile()
        }
    }

    // MARK: - Reconcile

    /// The core diff-and-apply. Fetches the full local library, diffs it
    /// against the cache's view of `HouseholdZone`, and applies mirror/unshare
    /// deltas.
    func reconcile() async {
        guard HouseholdManager.recordSharingEnabled else { return }

        // OWNER-ONLY GUARD — load-bearing, do not remove: a household MEMBER's
        // HouseholdCache holds the OWNER's records (fetched from the shared
        // database), not this device's own mirrors. If a member ran this
        // reconcile, every one of the owner's records would look like a local
        // deletion and get unshared out from under them. Only the owner, with
        // an active share, ever reconciles.
        guard HouseholdManager.shared.isHouseholdOwner, HouseholdManager.shared.hasActiveShare else {
            return
        }

        let context = PaperTrailModelContainer.shared.mainContext
        let localRecordModels = (try? context.fetch(FetchDescriptor<PurchaseRecord>())) ?? []
        let localAttachmentModels = (try? context.fetch(FetchDescriptor<Attachment>())) ?? []

        let localRecords = localRecordModels.map { SharedPurchaseRecordDTO(record: $0) }
        let localAttachments = localAttachmentModels.map { SharedAttachmentDTO(attachment: $0) }

        let cache = HouseholdCache.shared
        let diff = Self.computeDiff(
            localRecords: localRecords,
            localAttachments: localAttachments,
            cachedRecords: cache.purchaseRecords,
            cachedAttachments: cache.attachments,
            shareWholeLibrary: Self.shareWholeLibrary()
        )

        apply(diff)

        AppLogger.info(
            "Reconcile: \(diff.recordUpserts.count) record upserts, \(diff.recordDeletes.count) record deletes, "
                + "\(diff.attachmentUpserts.count) attachment upserts, \(diff.attachmentDeletes.count) attachment deletes",
            category: "cloud.sharing"
        )
    }

    private func apply(_ diff: Diff) {
        let cache = HouseholdCache.shared
        for dto in diff.recordUpserts {
            HouseholdSyncEngine.shared.mirror(dto: dto)
            cache.upsert(dto)
        }
        for id in diff.recordDeletes {
            HouseholdSyncEngine.shared.unshare(id: id)
            cache.removePurchaseRecord(id: id)
        }
        for dto in diff.attachmentUpserts {
            HouseholdSyncEngine.shared.mirror(dto: dto)
            cache.upsert(dto)
        }
        for id in diff.attachmentDeletes {
            HouseholdSyncEngine.shared.unshareAttachment(id: id)
            cache.removeAttachment(id: id)
        }
    }

    /// `UserDefaults.bool(forKey:)` returns `false` when the key is unset, but
    /// `HouseholdView`'s `@AppStorage("household.shareWholeLibrary")` default
    /// is `true` — read via `object(forKey:)` to preserve that default instead
    /// of silently treating "never opened Settings" as "share nothing".
    private static func shareWholeLibrary() -> Bool {
        (UserDefaults.standard.object(forKey: shareWholeLibraryDefaultsKey) as? Bool) ?? true
    }

    // MARK: - Explicit per-record actions

    /// Share one record (and its attachments) immediately — the per-record
    /// toggle in `RecordDetailView`. Optimistic: mirrors + upserts into the
    /// cache right away rather than waiting for the next reconcile.
    func share(recordID: UUID) {
        guard HouseholdManager.recordSharingEnabled else { return }
        let context = PaperTrailModelContainer.shared.mainContext
        guard let record = try? context.fetch(
            FetchDescriptor<PurchaseRecord>(predicate: #Predicate { $0.id == recordID })
        ).first else {
            AppLogger.error("share(recordID:) called for unknown record \(recordID)", category: "cloud.sharing")
            return
        }

        let recordDTO = SharedPurchaseRecordDTO(record: record)
        HouseholdSyncEngine.shared.mirror(dto: recordDTO)
        HouseholdCache.shared.upsert(recordDTO)

        // Attachment.recordID is Optional<UUID> and there's no persisted
        // @Relationship to filter through (see docs/PROJECT_STATE.md) — fetch
        // all and filter in memory, matching how LibraryView/RecordDetailView
        // already look up a record's attachments.
        let allAttachments = (try? context.fetch(FetchDescriptor<Attachment>())) ?? []
        let attachments = allAttachments.filter { $0.recordID == recordID }
        for attachment in attachments {
            let dto = SharedAttachmentDTO(attachment: attachment)
            HouseholdSyncEngine.shared.mirror(dto: dto)
            HouseholdCache.shared.upsert(dto)
        }

        AppLogger.info("Shared record \(recordID) (\(attachments.count) attachment(s))", category: "cloud.sharing")
    }

    /// Unshare one record (and its mirrored attachments) immediately.
    func unshare(recordID: UUID) {
        guard HouseholdManager.recordSharingEnabled else { return }

        HouseholdSyncEngine.shared.unshare(id: recordID)
        HouseholdCache.shared.removePurchaseRecord(id: recordID)

        let mirroredAttachments = HouseholdCache.shared.attachments(forRecordID: recordID)
        for attachment in mirroredAttachments {
            HouseholdSyncEngine.shared.unshareAttachment(id: attachment.id)
            HouseholdCache.shared.removeAttachment(id: attachment.id)
        }

        AppLogger.info("Unshared record \(recordID) (\(mirroredAttachments.count) attachment(s))", category: "cloud.sharing")
    }

    // MARK: - Pure diff (unit-testable, no CloudKit/SwiftData)

    /// Compute the mirror/unshare delta between the local library and the
    /// cache's current view of `HouseholdZone`.
    ///
    /// - wholeLibrary ON: every local record is a target.
    /// - wholeLibrary OFF: only records already present in the cache are
    ///   targets — the zone is the source of truth for "is this shared?", and
    ///   flipping the toggle OFF must never retroactively unshare records that
    ///   were explicitly shared per-record (only local delete / explicit
    ///   unshare removes a record from the zone).
    /// - Deletes fire only for cached records that no longer exist locally at
    ///   all (owner deleted them) — never merely because they fell outside
    ///   `shareWholeLibrary`'s target set.
    static func computeDiff(
        localRecords: [SharedPurchaseRecordDTO],
        localAttachments: [SharedAttachmentDTO],
        cachedRecords: [SharedPurchaseRecordDTO],
        cachedAttachments: [SharedAttachmentDTO],
        shareWholeLibrary: Bool
    ) -> Diff {
        var diff = Diff()

        let localRecordsByID = Dictionary(uniqueKeysWithValues: localRecords.map { ($0.id, $0) })
        let cachedRecordsByID = Dictionary(uniqueKeysWithValues: cachedRecords.map { ($0.id, $0) })

        let targetIDs: Set<UUID> = shareWholeLibrary
            ? Set(localRecordsByID.keys)
            : Set(cachedRecordsByID.keys)

        for id in targetIDs {
            guard let localDTO = localRecordsByID[id] else { continue }
            if cachedRecordsByID[id] != localDTO {
                diff.recordUpserts.append(localDTO)
            }
        }

        for id in cachedRecordsByID.keys where localRecordsByID[id] == nil {
            diff.recordDeletes.append(id)
        }

        // Attachments only mirror for records that are both a target AND
        // still present locally (a record queued for deletion above carries
        // its attachments with it, handled by the orphan check below).
        let sharedRecordIDs = targetIDs.intersection(localRecordsByID.keys)
        let cachedAttachmentsByID = Dictionary(uniqueKeysWithValues: cachedAttachments.map { ($0.id, $0) })
        let localAttachmentsByID = Dictionary(uniqueKeysWithValues: localAttachments.map { ($0.id, $0) })

        for attachment in localAttachments {
            guard let recordID = attachment.recordID, sharedRecordIDs.contains(recordID) else { continue }
            if cachedAttachmentsByID[attachment.id] != attachment {
                diff.attachmentUpserts.append(attachment)
            }
        }

        for cachedAttachment in cachedAttachments {
            let stillLocal = localAttachmentsByID[cachedAttachment.id] != nil
            let recordStillShared = cachedAttachment.recordID.map { sharedRecordIDs.contains($0) } ?? false
            if !stillLocal || !recordStillShared {
                diff.attachmentDeletes.append(cachedAttachment.id)
            }
        }

        return diff
    }
}
