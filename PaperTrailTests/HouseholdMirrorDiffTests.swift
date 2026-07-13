import Testing
import Foundation
@testable import PaperTrail

/// Coverage for `HouseholdMirrorCoordinator.computeDiff` — the pure,
/// CloudKit/SwiftData-free diff at the heart of Milestone 4 Phase 3 mirroring
/// (see docs/SHARING_ARCHITECTURE.md). Each test builds local/cached DTO sets
/// directly rather than going through SwiftData or CKSyncEngine.
///
/// `computeDiff` produces upserts ONLY — deletion requires positive evidence
/// (an actual local delete, routed through `HouseholdMirrorCoordinator`'s
/// explicit `recordDeleted`/`attachmentDeleted` hooks) and is never inferred
/// here. See the `Diff` doc comment for the mass-unshare bug this fixes: a
/// cached-but-not-local record is indistinguishable from a partial/empty
/// SwiftData read (a second owner device before its first sync, a reinstall,
/// a transient fetch error), so the old delete-from-absence behavior could
/// mass-unshare an entire household zone from a merely-empty local library.
struct HouseholdMirrorDiffTests {

    private func purchase(id: UUID = UUID(), productName: String = "Toaster") -> SharedPurchaseRecordDTO {
        SharedPurchaseRecordDTO(id: id, productName: productName)
    }

    private func attachment(id: UUID = UUID(), recordID: UUID?, filename: String = "a.jpg") -> SharedAttachmentDTO {
        SharedAttachmentDTO(id: id, recordID: recordID, typeRaw: AttachmentType.receipt.rawValue, localFilename: filename)
    }

    // MARK: (a) wholeLibrary ON mirrors new records + attachments

    @Test func wholeLibraryOnMirrorsNewRecordsAndAttachments() {
        let recordID = UUID()
        let record = purchase(id: recordID)
        let attachmentDTO = attachment(id: UUID(), recordID: recordID)

        let diff = HouseholdMirrorCoordinator.computeDiff(
            localRecords: [record],
            localAttachments: [attachmentDTO],
            cachedRecords: [],
            cachedAttachments: [],
            shareWholeLibrary: true
        )

        #expect(diff.recordUpserts == [record])
        #expect(diff.attachmentUpserts == [attachmentDTO])
    }

    // MARK: (b) changed DTO upserts, unchanged DTO no-ops

    @Test func changedDTOUpsertsUnchangedDTOIsNoOp() {
        let unchangedID = UUID()
        let changedID = UUID()

        let unchanged = purchase(id: unchangedID, productName: "Same")
        let changedOld = purchase(id: changedID, productName: "Old name")
        let changedNew = purchase(id: changedID, productName: "New name")

        let diff = HouseholdMirrorCoordinator.computeDiff(
            localRecords: [unchanged, changedNew],
            localAttachments: [],
            cachedRecords: [unchanged, changedOld],
            cachedAttachments: [],
            shareWholeLibrary: true
        )

        #expect(diff.recordUpserts == [changedNew])
    }

    // MARK: (c) REGRESSION — cached-only records/attachments are never deleted
    //
    // This is the mass-unshare regression test (Fix 1, CRITICAL): a record
    // present in the cache but absent from the local SwiftData fetch used to
    // be interpreted as "the owner deleted it" and queued an unshare. That's
    // indistinguishable from a second owner device syncing for the first
    // time, a reinstall, or `context.fetch` throwing. `computeDiff` must
    // produce nothing at all for cached-only data — no upserts (it's not
    // local), and structurally no deletes (the field doesn't exist anymore).

    @Test func cachedOnlyRecordsAreNeverDeleted_swiftDataLagSafety() {
        let recordID = UUID()
        let attachmentID = UUID()
        let cachedRecord = purchase(id: recordID)
        let cachedAttachment = attachment(id: attachmentID, recordID: recordID)

        let diff = HouseholdMirrorCoordinator.computeDiff(
            localRecords: [],
            localAttachments: [],
            cachedRecords: [cachedRecord],
            cachedAttachments: [cachedAttachment],
            shareWholeLibrary: true
        )

        #expect(diff == HouseholdMirrorCoordinator.Diff())
        #expect(diff.recordUpserts.isEmpty)
        #expect(diff.attachmentUpserts.isEmpty)
    }

    @Test func cachedOnlyAttachmentsAreNeverDeleted_swiftDataLagSafety() {
        let survivingRecordID = UUID()
        let deletedRecordID = UUID()
        let survivingRecord = purchase(id: survivingRecordID)
        let cachedDeletedRecord = purchase(id: deletedRecordID)
        let survivingAttachment = attachment(id: UUID(), recordID: survivingRecordID)
        // Cached attachment whose record no longer shows up in the local
        // fetch at all — the old code called this "orphaned" and deleted it.
        let cachedOnlyAttachment = attachment(id: UUID(), recordID: deletedRecordID)

        let diff = HouseholdMirrorCoordinator.computeDiff(
            localRecords: [survivingRecord],
            localAttachments: [survivingAttachment],
            cachedRecords: [cachedDeletedRecord, survivingRecord],
            cachedAttachments: [cachedOnlyAttachment, survivingAttachment],
            shareWholeLibrary: true
        )

        // Nothing changed for either record, so no upserts; and again,
        // structurally, there is nothing here that could ever delete.
        #expect(diff.recordUpserts.isEmpty)
        #expect(diff.attachmentUpserts.isEmpty)
    }

    // MARK: (d) wholeLibrary OFF keeps cached records updated, adds nothing new

    @Test func wholeLibraryOffUpdatesCachedRecordsButAddsNothingNew() {
        let cachedID = UUID()
        let newLocalOnlyID = UUID()

        let cachedOld = purchase(id: cachedID, productName: "Old name")
        let cachedNew = purchase(id: cachedID, productName: "New name")
        let newLocalOnly = purchase(id: newLocalOnlyID, productName: "Never shared")

        let diff = HouseholdMirrorCoordinator.computeDiff(
            localRecords: [cachedNew, newLocalOnly],
            localAttachments: [],
            cachedRecords: [cachedOld],
            cachedAttachments: [],
            shareWholeLibrary: false
        )

        #expect(diff.recordUpserts == [cachedNew])
    }

    // MARK: (e) wholeLibrary OFF (flipped from ON) does not touch unchanged cached records

    @Test func wholeLibraryOffDoesNotDeleteUnchangedCachedRecords() {
        let recordID = UUID()
        let record = purchase(id: recordID)

        let diff = HouseholdMirrorCoordinator.computeDiff(
            localRecords: [record],
            localAttachments: [],
            cachedRecords: [record],
            cachedAttachments: [],
            shareWholeLibrary: false
        )

        #expect(diff.recordUpserts.isEmpty)
    }

    // MARK: (g) duplicate ids in input must not crash — last one wins (Fix 8)

    @Test func computeDiffDuplicateLocalRecordIDsLastWinsWithoutCrashing() {
        let id = UUID()
        let first = purchase(id: id, productName: "First")
        let second = purchase(id: id, productName: "Second")

        let diff = HouseholdMirrorCoordinator.computeDiff(
            localRecords: [first, second],
            localAttachments: [],
            cachedRecords: [],
            cachedAttachments: [],
            shareWholeLibrary: true
        )

        #expect(diff.recordUpserts == [second])
    }

    @Test func computeDiffDuplicateCachedRecordIDsLastWinsWithoutCrashing() {
        let id = UUID()
        let local = purchase(id: id, productName: "Local")
        let cachedFirst = purchase(id: id, productName: "CachedFirst")
        let cachedSecond = purchase(id: id, productName: "CachedSecond")

        // Corrupted cache JSON with a duplicate id: must not crash, and the
        // diff logic just sees whichever cached value wins the tiebreak.
        let diff = HouseholdMirrorCoordinator.computeDiff(
            localRecords: [local],
            localAttachments: [],
            cachedRecords: [cachedFirst, cachedSecond],
            cachedAttachments: [],
            shareWholeLibrary: true
        )

        #expect(diff.recordUpserts == [local])
    }
}
