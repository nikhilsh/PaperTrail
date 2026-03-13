import SwiftUI

struct LibraryView: View {
    @State private var searchText = ""
    @State private var records: [PurchaseRecord] = [.preview]

    private var filteredRecords: [PurchaseRecord] {
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
                PurchaseRecordCard(record: record)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .overlay {
            if filteredRecords.isEmpty {
                ContentUnavailableView(
                    "No saved purchases yet",
                    systemImage: "doc.text.image",
                    description: Text("Use Capture to scan a receipt or warranty card.")
                )
            }
        }
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search products, stores, notes")
    }
}

private struct PurchaseRecordCard: View {
    let record: PurchaseRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.productName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let merchantName = record.merchantName {
                        Label(merchantName, systemImage: "storefront")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                AttachmentBadge(count: record.attachments.count)
            }

            HStack(spacing: 12) {
                if let purchaseDate = record.purchaseDate {
                    Label {
                        Text(purchaseDate, format: .dateTime.day().month().year())
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let warrantyExpiryDate = record.warrantyExpiryDate {
                    Label {
                        Text(warrantyExpiryDate, format: .dateTime.day().month().year())
                    } icon: {
                        Image(systemName: "shield")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let notes = record.notes, notes.isEmpty == false {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct AttachmentBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
            Text("\(count)")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.blue)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.12), in: Capsule())
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
}
