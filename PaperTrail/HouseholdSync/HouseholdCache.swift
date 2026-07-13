import CloudKit
import Foundation
import Observation

/// Local persistence for records shared TO this device (the member side of
/// household sharing, and the owner's own bookkeeping of `CKSyncEngine`
/// state). This is deliberately **not** the SwiftData store — see
/// docs/SHARING_ARCHITECTURE.md: inserting mirrored records into SwiftData
/// would re-upload them into this device's own private database and
/// duplicate the data. Instead they live here as plain JSON files under
/// `Application Support/HouseholdSync/`.
///
/// Kept dependency-free (no CKContainer, no network) so it's trivially
/// unit-testable: inject the directory URL in `init`.
///
/// `@Observable` (Phase 3) so views (`LibraryView`'s "Shared with me" section,
/// `RecordDetailView`'s share toggle) re-render as mirrored/shared-in records
/// change. `HouseholdSyncEngine`'s default-argument `HouseholdCache` used to be
/// a private, unobservable instance no view could ever see — `.shared` fixes
/// that; tests keep injecting their own temp-directory instance via `init`.
@MainActor
@Observable
final class HouseholdCache {

    /// The instance every view and sync engine should use. See the type doc
    /// above — the previous per-engine private instance was a latent bug.
    static let shared = HouseholdCache()

    private let directoryURL: URL
    private let purchaseRecordsFileURL: URL
    private let attachmentsFileURL: URL

    private(set) var purchaseRecords: [SharedPurchaseRecordDTO] = []
    private(set) var attachments: [SharedAttachmentDTO] = []

    // nonisolated: default arguments are evaluated outside the actor, so the
    // initializer chain must be callable from a nonisolated context. Both only
    // touch stored properties / FileManager paths.
    nonisolated init(directoryURL: URL = HouseholdCache.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
        purchaseRecordsFileURL = directoryURL.appendingPathComponent("purchase-records.json")
        attachmentsFileURL = directoryURL.appendingPathComponent("attachments.json")
    }

    nonisolated static func defaultDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("HouseholdSync", isDirectory: true)
    }

    // MARK: - Load / Save

    /// Load persisted records from disk, replacing in-memory state. Missing
    /// files are treated as empty (first launch / nothing shared yet).
    func load() {
        purchaseRecords = Self.loadJSON(from: purchaseRecordsFileURL) ?? []
        attachments = Self.loadJSON(from: attachmentsFileURL) ?? []
    }

    /// Persist current in-memory state to disk, creating the directory on
    /// first save.
    func save() {
        ensureDirectoryExists()
        Self.saveJSON(purchaseRecords, to: purchaseRecordsFileURL)
        Self.saveJSON(attachments, to: attachmentsFileURL)
    }

    // MARK: - Purchase records

    /// Insert or replace (by `id`) a mirrored purchase record, then persist.
    func upsert(_ dto: SharedPurchaseRecordDTO) {
        if let index = purchaseRecords.firstIndex(where: { $0.id == dto.id }) {
            purchaseRecords[index] = dto
        } else {
            purchaseRecords.append(dto)
        }
        save()
    }

    func removePurchaseRecord(id: UUID) {
        purchaseRecords.removeAll { $0.id == id }
        save()
    }

    // MARK: - Attachments

    /// Insert or replace (by `id`) a mirrored attachment, then persist.
    func upsert(_ dto: SharedAttachmentDTO) {
        if let index = attachments.firstIndex(where: { $0.id == dto.id }) {
            attachments[index] = dto
        } else {
            attachments.append(dto)
        }
        save()
    }

    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
        save()
    }

    /// Look up a mirrored purchase record by id — used by the per-record share
    /// toggle (`RecordDetailView`) to answer "is this record shared?" without
    /// the caller reaching into `purchaseRecords` directly.
    func purchaseRecord(id: UUID) -> SharedPurchaseRecordDTO? {
        purchaseRecords.first { $0.id == id }
    }

    /// All mirrored attachments for a given purchase record id.
    func attachments(forRecordID id: UUID) -> [SharedAttachmentDTO] {
        attachments.filter { $0.recordID == id }
    }

    /// Purge everything — used when the household zone is deleted upstream or
    /// the CloudKit account changes (see `HouseholdSyncEngine`).
    func removeAll() {
        purchaseRecords.removeAll()
        attachments.removeAll()
        save()
    }

    // MARK: - Engine state

    /// Raw, opaque bytes for a `CKSyncEngine.State.Serialization`, one file
    /// per engine. Kept at the `Data` level (rather than decoding to the
    /// CloudKit type internally) so this class has no dependency on being
    /// able to construct a `CKSyncEngine.State.Serialization` — only
    /// `CKSyncEngine` itself ever produces real ones.
    func stateData(for kind: HouseholdSyncEngine.EngineKind) -> Data? {
        try? Data(contentsOf: stateFileURL(for: kind))
    }

    func setStateData(_ data: Data?, for kind: HouseholdSyncEngine.EngineKind) {
        let url = stateFileURL(for: kind)
        guard let data else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        ensureDirectoryExists()
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.error("Failed to write engine state for \(kind.rawValue): \(error.localizedDescription)", category: "cloud.sharing")
        }
    }

    /// Typed convenience over `stateData(for:)` — `CKSyncEngine.State.Serialization`
    /// is `Codable`, so this just JSON-encodes/decodes it directly.
    func stateSerialization(for kind: HouseholdSyncEngine.EngineKind) -> CKSyncEngine.State.Serialization? {
        guard let data = stateData(for: kind) else { return nil }
        do {
            return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            AppLogger.error("Failed to decode engine state for \(kind.rawValue): \(error.localizedDescription)", category: "cloud.sharing")
            return nil
        }
    }

    func setStateSerialization(_ serialization: CKSyncEngine.State.Serialization?, for kind: HouseholdSyncEngine.EngineKind) {
        guard let serialization else {
            setStateData(nil, for: kind)
            return
        }
        do {
            let data = try JSONEncoder().encode(serialization)
            setStateData(data, for: kind)
        } catch {
            AppLogger.error("Failed to encode engine state for \(kind.rawValue): \(error.localizedDescription)", category: "cloud.sharing")
        }
    }

    // MARK: - Helpers

    private func stateFileURL(for kind: HouseholdSyncEngine.EngineKind) -> URL {
        directoryURL.appendingPathComponent("engine-state-\(kind.rawValue).json")
    }

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private static func loadJSON<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else {
            AppLogger.error("Failed to encode HouseholdCache data for \(url.lastPathComponent)", category: "cloud.sharing")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            AppLogger.error("Failed to write HouseholdCache file \(url.lastPathComponent): \(error.localizedDescription)", category: "cloud.sharing")
        }
    }
}
