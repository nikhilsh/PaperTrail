import Testing
import Foundation
@testable import PaperTrail

/// Coverage for `HouseholdCache`'s local JSON persistence (Milestone 4 Phase
/// 1 — household record sharing). Each test gets its own temp directory so
/// runs never collide or leak state between tests.
struct HouseholdCacheTests {

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("HouseholdCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func samplePurchaseDTO(id: UUID = UUID(), productName: String = "Toaster") -> SharedPurchaseRecordDTO {
        SharedPurchaseRecordDTO(id: id, productName: productName)
    }

    private func sampleAttachmentDTO(id: UUID = UUID(), localFilename: String = "a.jpg") -> SharedAttachmentDTO {
        SharedAttachmentDTO(id: id, typeRaw: AttachmentType.receipt.rawValue, localFilename: localFilename)
    }

    // MARK: - Save / load round trip

    @Test @MainActor func saveAndLoadRoundTripsPurchaseRecordsAndAttachments() {
        let dir = makeTempDirectory()
        let cache = HouseholdCache(directoryURL: dir)

        let purchase = samplePurchaseDTO()
        let attachment = sampleAttachmentDTO()
        cache.upsert(purchase)
        cache.upsert(attachment)

        // Fresh instance pointed at the same directory should load what the
        // first instance persisted.
        let reloaded = HouseholdCache(directoryURL: dir)
        reloaded.load()

        #expect(reloaded.purchaseRecords == [purchase])
        #expect(reloaded.attachments == [attachment])
    }

    @Test @MainActor func loadOnEmptyDirectoryIsEmpty() {
        let dir = makeTempDirectory()
        let cache = HouseholdCache(directoryURL: dir)
        cache.load()
        #expect(cache.purchaseRecords.isEmpty)
        #expect(cache.attachments.isEmpty)
    }

    @Test @MainActor func saveCreatesDirectoryOnFirstSave() {
        let dir = makeTempDirectory()
        #expect(!FileManager.default.fileExists(atPath: dir.path))

        let cache = HouseholdCache(directoryURL: dir)
        cache.upsert(samplePurchaseDTO())

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(isDirectory.boolValue)
    }

    // MARK: - Upsert / remove

    @Test @MainActor func upsertReplacesExistingRecordByID() {
        let dir = makeTempDirectory()
        let cache = HouseholdCache(directoryURL: dir)

        let id = UUID()
        cache.upsert(samplePurchaseDTO(id: id, productName: "Toaster"))
        cache.upsert(samplePurchaseDTO(id: id, productName: "Blender"))

        #expect(cache.purchaseRecords.count == 1)
        #expect(cache.purchaseRecords.first?.productName == "Blender")
    }

    @Test @MainActor func upsertReplacesExistingAttachmentByID() {
        let dir = makeTempDirectory()
        let cache = HouseholdCache(directoryURL: dir)

        let id = UUID()
        cache.upsert(sampleAttachmentDTO(id: id, localFilename: "first.jpg"))
        cache.upsert(sampleAttachmentDTO(id: id, localFilename: "second.jpg"))

        #expect(cache.attachments.count == 1)
        #expect(cache.attachments.first?.localFilename == "second.jpg")
    }

    @Test @MainActor func removePurchaseRecordByID() {
        let dir = makeTempDirectory()
        let cache = HouseholdCache(directoryURL: dir)

        let keep = samplePurchaseDTO(productName: "Keep me")
        let remove = samplePurchaseDTO(productName: "Remove me")
        cache.upsert(keep)
        cache.upsert(remove)

        cache.removePurchaseRecord(id: remove.id)

        #expect(cache.purchaseRecords == [keep])
    }

    @Test @MainActor func removeAttachmentByID() {
        let dir = makeTempDirectory()
        let cache = HouseholdCache(directoryURL: dir)

        let keep = sampleAttachmentDTO(localFilename: "keep.jpg")
        let remove = sampleAttachmentDTO(localFilename: "remove.jpg")
        cache.upsert(keep)
        cache.upsert(remove)

        cache.removeAttachment(id: remove.id)

        #expect(cache.attachments == [keep])
    }

    @Test @MainActor func removeAllClearsBothCollections() {
        let dir = makeTempDirectory()
        let cache = HouseholdCache(directoryURL: dir)
        cache.upsert(samplePurchaseDTO())
        cache.upsert(sampleAttachmentDTO())

        cache.removeAll()

        #expect(cache.purchaseRecords.isEmpty)
        #expect(cache.attachments.isEmpty)

        // And the clear itself must persist.
        let reloaded = HouseholdCache(directoryURL: dir)
        reloaded.load()
        #expect(reloaded.purchaseRecords.isEmpty)
        #expect(reloaded.attachments.isEmpty)
    }

    // MARK: - Engine state serialization

    @Test @MainActor func stateDataRoundTripsPerEngineKind() {
        let dir = makeTempDirectory()
        let cache = HouseholdCache(directoryURL: dir)

        let privateData = Data("private-engine-state".utf8)
        let sharedData = Data("shared-engine-state".utf8)
        cache.setStateData(privateData, for: .privateDB)
        cache.setStateData(sharedData, for: .sharedDB)

        #expect(cache.stateData(for: .privateDB) == privateData)
        #expect(cache.stateData(for: .sharedDB) == sharedData)

        // A fresh instance must be able to read what the first persisted.
        let reloaded = HouseholdCache(directoryURL: dir)
        #expect(reloaded.stateData(for: .privateDB) == privateData)
        #expect(reloaded.stateData(for: .sharedDB) == sharedData)
    }

    @Test @MainActor func stateDataIsNilWhenNeverSet() {
        let dir = makeTempDirectory()
        let cache = HouseholdCache(directoryURL: dir)
        #expect(cache.stateData(for: .privateDB) == nil)
    }

    @Test @MainActor func settingStateDataToNilRemovesIt() {
        let dir = makeTempDirectory()
        let cache = HouseholdCache(directoryURL: dir)
        cache.setStateData(Data("something".utf8), for: .privateDB)
        #expect(cache.stateData(for: .privateDB) != nil)

        cache.setStateData(nil, for: .privateDB)
        #expect(cache.stateData(for: .privateDB) == nil)
    }
}
