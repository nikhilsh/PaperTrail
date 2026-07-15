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
    ///
    /// **Deletion is not part of this diff.** Earlier versions inferred a
    /// delete from "cached but not in the local SwiftData fetch," which is
    /// indistinguishable from a partial/empty local library (a second owner
    /// device before its first full sync, a reinstall, or a transient
    /// `context.fetch` error) — that bug mass-unshared an entire household
    /// zone from a merely-empty read. Deletion now requires **positive
    /// evidence**: an actual local delete, routed through the explicit hooks
    /// below (`recordDeleted`, `attachmentDeleted`), called directly from the
    /// app's delete call sites (`RecordDetailView`, `LibraryView`). This type
    /// only ever adds things to the zone.
    nonisolated struct Diff: Equatable {
        var recordUpserts: [SharedPurchaseRecordDTO] = []
        var attachmentUpserts: [SharedAttachmentDTO] = []
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
            // Cold launch never posts willEnterForeground, so the foreground
            // poll above doesn't cover it — without this, a member who
            // force-quit sees a stale (or empty) shared library until the
            // first background→foreground cycle.
            await HouseholdSyncEngine.shared.fetchChanges()
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

        // do/catch, not `(try? ...) ?? []`: a fetch FAILURE must never be
        // treated as an empty library. `?? []` made every field-error /
        // transient SwiftData hiccup look identical to "user deleted
        // everything," which fed straight into a mass unshare. Bail out of
        // this reconcile pass entirely and let the next trigger (debounced
        // save, foreground, or the periodic poll) retry.
        let context = PaperTrailModelContainer.shared.mainContext
        let localRecordModels: [PurchaseRecord]
        let localAttachmentModels: [Attachment]
        do {
            localRecordModels = try context.fetch(FetchDescriptor<PurchaseRecord>())
            localAttachmentModels = try context.fetch(FetchDescriptor<Attachment>())
        } catch {
            AppLogger.error("Reconcile aborted: SwiftData fetch failed: \(error.localizedDescription)", category: "cloud.sharing")
            return
        }

        let localRecords = localRecordModels.map { SharedPurchaseRecordDTO(record: $0) }
        let localAttachments = localAttachmentModels.map { SharedAttachmentDTO(attachment: $0) }

        let cache = HouseholdCache.shared
        let diff = Self.computeDiff(
            localRecords: localRecords,
            localAttachments: localAttachments,
            cachedRecords: cache.purchaseRecords,
            cachedAttachments: cache.attachments,
            shareWholeLibrary: Self.effectiveShareWholeLibrary()
        )

        apply(diff)

        AppLogger.info(
            "Reconcile: \(diff.recordUpserts.count) record upserts, \(diff.attachmentUpserts.count) attachment upserts",
            category: "cloud.sharing"
        )
    }

    private func apply(_ diff: Diff) {
        let cache = HouseholdCache.shared
        cache.withBatchedSaves {
            for dto in diff.recordUpserts {
                HouseholdSyncEngine.shared.mirror(dto: dto)
                cache.upsert(dto)
            }
            for dto in diff.attachmentUpserts {
                HouseholdSyncEngine.shared.mirror(dto: dto)
                cache.upsert(dto)
            }
        }
    }

    /// `UserDefaults.bool(forKey:)` returns `false` when the key is unset, but
    /// `HouseholdView`'s `@AppStorage("household.shareWholeLibrary")` default
    /// is `true` — read via `object(forKey:)` to preserve that default instead
    /// of silently treating "never opened Settings" as "share nothing". Not
    /// `private`: `HouseholdSyncEngine`'s zone-resident settings-record
    /// builder (`mirrorSettings`/`pendingRecord(for:)`) reads this same
    /// helper so the record's local-default fallback and this toggle's own
    /// default can never diverge (Fix 9).
    static func localShareWholeLibraryDefault() -> Bool {
        (UserDefaults.standard.object(forKey: shareWholeLibraryDefaultsKey) as? Bool) ?? true
    }

    /// The policy actually used to decide what mirrors (Fix 9 — see
    /// docs/SHARING_ARCHITECTURE.md "zone-resident settings"). A per-device
    /// `UserDefaults` toggle must never let one owner device silently
    /// override another's choice once a share exists, so the zone-resident
    /// `HouseholdSettings` record (mirrored from whichever device set it) is
    /// authoritative once it's arrived. Until then: an empty cache means this
    /// is a brand-new share — safe to fall back to this device's own local
    /// toggle. A non-empty cache with no settings record yet means some other
    /// device already has state we haven't fetched — default to NOT
    /// auto-mirroring new records rather than guessing, since guessing "on"
    /// could re-share something another device deliberately narrowed.
    private static func effectiveShareWholeLibrary() -> Bool {
        let cache = HouseholdCache.shared
        if let setting = cache.shareWholeLibrarySetting {
            return setting
        }
        if !cache.purchaseRecords.isEmpty {
            return false
        }
        return localShareWholeLibraryDefault()
    }

    /// Called when the owner explicitly flips the whole-library toggle
    /// (`HouseholdView`). Optimistically records the new policy in the cache
    /// (so `effectiveShareWholeLibrary()` reflects it immediately, without
    /// waiting on a round trip), queues the zone-resident settings record
    /// write, then reconciles so the new policy takes effect right away.
    /// No-op when record sharing is disabled — matches the pre-Fix-9
    /// behavior of a bare `reconcile()` call, which itself no-ops when the
    /// flag is off.
    func shareWholeLibraryChanged(_ newValue: Bool) {
        guard HouseholdManager.recordSharingEnabled else { return }
        HouseholdCache.shared.setShareWholeLibrarySetting(newValue)
        HouseholdSyncEngine.shared.mirrorSettings(shareWholeLibrary: newValue)
        Task { await reconcile() }
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

    // MARK: - Explicit deletion hooks (Fix 1)

    /// The ONLY path that removes a mirrored record from `HouseholdZone` in
    /// response to a local delete — deletion requires positive evidence (a
    /// real `modelContext.delete`), never an inference from `computeDiff`.
    /// Called from the app's two record-delete call sites,
    /// `RecordDetailView.deleteRecord()` and `LibraryView.deleteRecord(_:)`.
    /// No-op when record sharing is disabled.
    func recordDeleted(recordID: UUID, attachmentIDs: [UUID]) {
        guard HouseholdManager.recordSharingEnabled else { return }
        HouseholdSyncEngine.shared.unshare(id: recordID)
        for attachmentID in attachmentIDs {
            HouseholdSyncEngine.shared.unshareAttachment(id: attachmentID)
        }
        let cache = HouseholdCache.shared
        cache.withBatchedSaves {
            cache.removePurchaseRecord(id: recordID)
            for attachmentID in attachmentIDs {
                cache.removeAttachment(id: attachmentID)
            }
        }
        AppLogger.info("recordDeleted hook: unshared record \(recordID) (\(attachmentIDs.count) attachment(s))", category: "cloud.sharing")
    }

    /// Single-attachment counterpart to `recordDeleted` — wired wherever the
    /// app removes one attachment from a record without deleting the whole
    /// record (no such call site exists in the app today; kept for parity
    /// with `recordDeleted` and future UI).
    func attachmentDeleted(id: UUID) {
        guard HouseholdManager.recordSharingEnabled else { return }
        HouseholdSyncEngine.shared.unshareAttachment(id: id)
        HouseholdCache.shared.removeAttachment(id: id)
        AppLogger.info("attachmentDeleted hook: unshared attachment \(id)", category: "cloud.sharing")
    }

    // MARK: - Pure diff (unit-testable, no CloudKit/SwiftData)

    /// Compute the mirror delta between the local library and the cache's
    /// current view of `HouseholdZone`. **Upserts only** — see the `Diff`
    /// doc comment above for why deletion is never inferred here.
    ///
    /// - wholeLibrary ON: every local record is a target.
    /// - wholeLibrary OFF: only records already present in the cache are
    ///   targets — the zone is the source of truth for "is this shared?", and
    ///   flipping the toggle OFF must never retroactively unshare records that
    ///   were explicitly shared per-record (only local delete / explicit
    ///   unshare removes a record from the zone).
    // nonisolated: pure function (no actor state) — also lets the sync,
    // nonisolated unit tests call it directly.
    nonisolated static func computeDiff(
        localRecords: [SharedPurchaseRecordDTO],
        localAttachments: [SharedAttachmentDTO],
        cachedRecords: [SharedPurchaseRecordDTO],
        cachedAttachments: [SharedAttachmentDTO],
        shareWholeLibrary: Bool
    ) -> Diff {
        var diff = Diff()

        // uniquingKeysWith: a corrupted cache JSON (or a duplicate id in the
        // local fetch) must not crash reconcile — last-one-wins is a safe,
        // arbitrary tiebreak for data that's already inconsistent.
        let localRecordsByID = Dictionary(localRecords.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let cachedRecordsByID = Dictionary(cachedRecords.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        let targetIDs: Set<UUID> = shareWholeLibrary
            ? Set(localRecordsByID.keys)
            : Set(cachedRecordsByID.keys)

        for id in targetIDs {
            guard let localDTO = localRecordsByID[id] else { continue }
            if cachedRecordsByID[id] != localDTO {
                diff.recordUpserts.append(localDTO)
            }
        }

        // Attachments only mirror for records that are both a target AND
        // still present locally.
        let sharedRecordIDs = targetIDs.intersection(localRecordsByID.keys)
        let cachedAttachmentsByID = Dictionary(cachedAttachments.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        for attachment in localAttachments {
            guard let recordID = attachment.recordID, sharedRecordIDs.contains(recordID) else { continue }
            if cachedAttachmentsByID[attachment.id] != attachment {
                diff.attachmentUpserts.append(attachment)
            }
        }

        return diff
    }
}
