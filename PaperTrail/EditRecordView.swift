import SwiftUI

struct EditRecordView: View {
    @EnvironmentObject private var store: PurchaseRecordStore
    @Environment(\.dismiss) private var dismiss

    let recordID: UUID

    @State private var productName: String
    @State private var merchantName: String
    @State private var notes: String

    init(record: PurchaseRecord) {
        recordID = record.id
        _productName = State(initialValue: record.productName)
        _merchantName = State(initialValue: record.merchantName ?? "")
        _notes = State(initialValue: record.notes ?? "")
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Product name", text: $productName)
                TextField("Store", text: $merchantName)
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
            }
        }
        .navigationTitle("Edit Record")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveEdits()
                }
            }
        }
    }

    private func saveEdits() {
        guard let existing = store.records.first(where: { $0.id == recordID }) else { return }

        var updated = existing
        updated.productName = productName
        updated.merchantName = merchantName.isEmpty ? nil : merchantName
        updated.notes = notes.isEmpty ? nil : notes
        updated.updatedAt = .now

        store.update(updated)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        EditRecordView(record: .preview)
            .environmentObject(PurchaseRecordStore())
    }
}
