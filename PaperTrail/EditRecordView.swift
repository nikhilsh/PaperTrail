import SwiftUI

struct EditRecordView: View {
    @State private var productName: String
    @State private var merchantName: String
    @State private var notes: String

    init(record: PurchaseRecord) {
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
    }
}

#Preview {
    NavigationStack {
        EditRecordView(record: .preview)
    }
}
