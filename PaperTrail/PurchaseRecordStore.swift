import Foundation
import Observation

@Observable
@MainActor
final class PurchaseRecordStore {
    private(set) var records: [PurchaseRecord]

    init(records: [PurchaseRecord]? = nil) {
        self.records = records ?? [.preview]
    }

    func add(_ record: PurchaseRecord) {
        records.insert(record, at: 0)
    }

    func update(_ record: PurchaseRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
    }
}
