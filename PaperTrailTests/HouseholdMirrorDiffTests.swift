import Testing
import Foundation
@testable import PaperTrail

/// Coverage for `HouseholdMirrorCoordinator.computeDiff` — the pure,
/// CloudKit/SwiftData-free diff at the heart of Milestone 4 Phase 3 mirroring
/// (see docs/SHARING_ARCHITECTURE.md). Each test builds local/cached DTO sets
/// directly rather than going through SwiftData or CKSyncEngine.
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
        #expect(diff.recordDeletes.isEmpty)
        #expect(diff.attachmentDeletes.isEmpty)
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
        #expect(diff.recordDeletes.isEmpty)
    }

    // MARK: (c) local delete removes record + its attachments

    @Test func localDeleteProducesRecordAndAttachmentDeletes() {
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

        #expect(diff.recordDeletes == [recordID])
        #expect(diff.attachmentDeletes == [attachmentID])
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
        #expect(diff.recordDeletes.isEmpty)
    }

    // MARK: (e) wholeLibrary OFF (flipped from ON) does not delete cached-but-unchanged records

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

        #expect(diff.recordDeletes.isEmpty)
        #expect(diff.recordUpserts.isEmpty)
    }

    // MARK: (f) attachment orphaned by record deletion is deleted

    @Test func attachmentOrphanedByRecordDeletionIsDeleted() {
        let deletedRecordID = UUID()
        let survivingRecordID = UUID()
        let orphanedAttachmentID = UUID()
        let survivingAttachmentID = UUID()

        let survivingRecord = purchase(id: survivingRecordID)
        let cachedDeletedRecord = purchase(id: deletedRecordID)
        let orphanedAttachment = attachment(id: orphanedAttachmentID, recordID: deletedRecordID)
        let survivingAttachment = attachment(id: survivingAttachmentID, recordID: survivingRecordID)

        let diff = HouseholdMirrorCoordinator.computeDiff(
            localRecords: [survivingRecord],
            localAttachments: [survivingAttachment],
            cachedRecords: [cachedDeletedRecord, survivingRecord],
            cachedAttachments: [orphanedAttachment, survivingAttachment],
            shareWholeLibrary: true
        )

        #expect(diff.attachmentDeletes == [orphanedAttachmentID])
        #expect(diff.recordDeletes == [deletedRecordID])
        #expect(!diff.attachmentDeletes.contains(survivingAttachmentID))
    }
}
