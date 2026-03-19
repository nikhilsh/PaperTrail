import SwiftUI
import SwiftData

enum LibrarySortOption: String, CaseIterable {
    case newest = "Newest"
    case oldest = "Oldest"
    case name = "Name"
    case warrantyExpiry = "Warranty Expiry"
}

enum LibraryFilterOption: String, CaseIterable {
    case all = "All"
    case active = "Active Warranty"
    case expiringSoon = "Expiring Soon"
    case expired = "Expired"
}

struct LibraryView: View {
    @Query(sort: \PurchaseRecord.updatedAt, order: .reverse) private var records: [PurchaseRecord]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var sortOption: LibrarySortOption = .newest
    @State private var filterOption: LibraryFilterOption = .all

    private var processedRecords: [PurchaseRecord] {
        var result = records

        // Filter
        switch filterOption {
        case .all: break
        case .active:
            result = result.filter { $0.warrantyStatus == .active }
        case .expiringSoon:
            result = result.filter { $0.warrantyStatus == .expiringSoon }
        case .expired:
            result = result.filter { $0.warrantyStatus == .expired }
        }

        // Search (including OCR text in attachments)
        if !searchText.isEmpty {
            result = result.filter { record in
                record.productName.localizedCaseInsensitiveContains(searchText)
                || (record.merchantName?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (record.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (record.category?.localizedCaseInsensitiveContains(searchText) ?? false)
                || record.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
                || record.attachments.contains { $0.ocrText?.localizedCaseInsensitiveContains(searchText) ?? false }
            }
        }

        // Sort
        switch sortOption {
        case .newest:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .oldest:
            result.sort { $0.updatedAt < $1.updatedAt }
        case .name:
            result.sort { $0.productName.localizedCompare($1.productName) == .orderedAscending }
        case .warrantyExpiry:
            result.sort { ($0.warrantyExpiryDate ?? .distantFuture) < ($1.warrantyExpiryDate ?? .distantFuture) }
        }

        return result
    }

    private var expiringSoonCount: Int {
        records.filter { $0.warrantyStatus == .expiringSoon }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LibrarySummaryRow(totalCount: records.count, expiringSoonCount: expiringSoonCount)

                // Sort & Filter controls
                HStack {
                    Menu {
                        ForEach(LibrarySortOption.allCases, id: \.self) { option in
                            Button {
                                sortOption = option
                            } label: {
                                if sortOption == option {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label(sortOption.rawValue, systemImage: "arrow.up.arrow.down")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }

                    Menu {
                        ForEach(LibraryFilterOption.allCases, id: \.self) { option in
                            Button {
                                filterOption = option
                            } label: {
                                if filterOption == option {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label(filterOption.rawValue, systemImage: "line.3.horizontal.decrease")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }

                    Spacer()
                }

                if processedRecords.isEmpty {
                    if records.isEmpty {
                        ContentUnavailableView(
                            "No saved purchases yet",
                            systemImage: "doc.text.image",
                            description: Text("Use Capture to scan a receipt or warranty card.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    } else {
                        ContentUnavailableView(
                            "No matches",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search or filter.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(processedRecords) { record in
                            NavigationLink {
                                RecordDetailView(record: record)
                            } label: {
                                PurchaseRecordCard(record: record)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    deleteRecord(record)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Library")
        .searchable(text: $searchText, prompt: "Search products, stores, OCR text, tags")
    }

    private func deleteRecord(_ record: PurchaseRecord) {
        for attachment in record.attachments {
            ImageStorageManager.delete(attachment.localFilename)
        }
        NotificationManager.shared.removeWarrantyReminders(for: record)
        modelContext.delete(record)
    }
}

// MARK: - Subviews

private struct LibrarySummaryRow: View {
    let totalCount: Int
    let expiringSoonCount: Int

    var body: some View {
        HStack(spacing: 12) {
            SummaryTile(title: "Saved", value: "\(totalCount)", systemImage: "tray.full")
            SummaryTile(
                title: "Expiring soon",
                value: "\(expiringSoonCount)",
                systemImage: "clock.badge.exclamationmark",
                highlight: expiringSoonCount > 0
            )
        }
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String
    let systemImage: String
    var highlight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(highlight ? .orange : .secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(highlight ? .orange : .primary)
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

                VStack(alignment: .trailing, spacing: 4) {
                    AttachmentBadge(count: record.attachments.count)

                    if let amount = record.formattedAmount {
                        Text(amount)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
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

                if record.warrantyExpiryDate != nil {
                    WarrantyBadge(status: record.warrantyStatus)
                }
            }

            // Tags
            if !record.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(record.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.1), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            if let notes = record.notes, !notes.isEmpty {
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

private struct WarrantyBadge: View {
    let status: WarrantyStatus

    private var color: Color {
        switch status {
        case .active: .green
        case .expiringSoon: .orange
        case .expired: .red
        case .unknown: .secondary
        }
    }

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
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
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
