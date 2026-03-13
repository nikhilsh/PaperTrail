import SwiftUI

struct LibraryView: View {
    @State private var searchText = ""
    @State private var records: [PurchaseRecord] = [.preview]

    var filteredRecords: [PurchaseRecord] {
        guard searchText.isEmpty == false else { return records }
        return records.filter {
            $0.productName.localizedCaseInsensitiveContains(searchText)
            || ($0.merchantName?.localizedCaseInsensitiveContains(searchText) ?? false)
            || ($0.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        List(filteredRecords) { record in
            NavigationLink {
                RecordDetailView(record: record)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.productName)
                        .font(.headline)

                    if let merchantName = record.merchantName {
                        Text(merchantName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let purchaseDate = record.purchaseDate {
                        Text(purchaseDate, format: .dateTime.day().month().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .overlay {
            if filteredRecords.isEmpty {
                ContentUnavailableView(
                    "No saved purchases yet",
                    systemImage: "doc.text.image",
                    description: Text("Start by capturing a receipt or warranty card.")
                )
            }
        }
        .navigationTitle("PaperTrail")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CaptureView()
                } label: {
                    Label("Capture", systemImage: "plus.viewfinder")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search receipts, stores, products")
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
}
