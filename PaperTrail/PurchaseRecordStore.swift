import Foundation
import SwiftUI

@MainActor
final class PurchaseRecordStore: ObservableObject {
    @Published private(set) var records: [PurchaseRecord]

    init(records: [PurchaseRecord] = [.preview]) {
        self.records = records
    }

    func add(_ record: PurchaseRecord) {
        records.insert(record, at: 0)
    }

    func update(_ record: PurchaseRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
    }
}
