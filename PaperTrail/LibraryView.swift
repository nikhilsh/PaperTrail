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

    private var expiringSoonCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now
        return records.filter {
            guard let warrantyExpiryDate = $0.warrantyExpiryDate else { return false }
            return warrantyExpiryDate <= cutoff
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LibrarySummaryRow(totalCount: records.count, expiringSoonCount: expiringSoonCount)

                if filteredRecords.isEmpty {
                    ContentUnavailableView(
                        "No saved purchases yet",
                        systemImage: "doc.text.image",
                        description: Text("Use Capture to scan a receipt or warranty card.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                } else {
                    VStack(spacing: 12) {
                        ForEach(filteredRecords) { record in
                            NavigationLink {
                                RecordDetailView(record: record)
                            } label: {
                                PurchaseRecordCard(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search products, stores, notes")
    }
}

private struct LibrarySummaryRow: View {
    let totalCount: Int
    let expiringSoonCount: Int

    var body: some View {
        HStack(spacing: 12) {
            SummaryTile(title: "Saved", value: "\(totalCount)", systemImage: "tray.full")
            SummaryTile(title: "Expiring soon", value: "\(expiringSoonCount)", systemImage: "clock.badge.exclamationmark")
        }
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
