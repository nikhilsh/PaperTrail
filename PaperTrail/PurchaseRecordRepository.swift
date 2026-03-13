import Foundation

protocol PurchaseRecordRepository {
    func fetchAll() async throws -> [PurchaseRecord]
    func save(_ record: PurchaseRecord) async throws
}

struct InMemoryPurchaseRecordRepository: PurchaseRecordRepository {
    func fetchAll() async throws -> [PurchaseRecord] {
        [.preview]
    }

    func save(_ record: PurchaseRecord) async throws {
        _ = record
    }
}
