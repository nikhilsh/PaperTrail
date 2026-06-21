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

enum LibraryDateFilterOption: String, CaseIterable {
    case any = "Any Date"
    case last30Days = "Last 30 Days"
    case thisYear = "This Year"
    case noDate = "No Purchase Date"
}

struct LibraryView: View {
    @Query(sort: \PurchaseRecord.updatedAt, order: .reverse) private var records: [PurchaseRecord]
    @Query private var allAttachments: [Attachment]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @State private var searchText = ""
    @State private var sortOption: LibrarySortOption = .newest
    @State private var filterOption: LibraryFilterOption = .all
    @State private var dateFilterOption: LibraryDateFilterOption = .any
    @State private var selectedCategory: String?
    @State private var selectedTag: String?

    private func attachments(for record: PurchaseRecord) -> [Attachment] {
        allAttachments.filter { $0.recordID == record.id }
    }

    private var availableCategories: [String] {
        sortedUnique(records.compactMap(\.category))
    }

    private var availableTags: [String] {
        sortedUnique(records.flatMap(\.tags))
    }

    private var activeFilterCount: Int {
        [
            filterOption != .all,
            dateFilterOption != .any,
            selectedCategory != nil,
            selectedTag != nil
        ].filter { $0 }.count
    }

    private var processedRecords: [PurchaseRecord] {
        var result = records
        let searchQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Warranty status
        switch filterOption {
        case .all: break
        case .active:
            result = result.filter { $0.warrantyStatus == .active }
        case .expiringSoon:
            result = result.filter { $0.warrantyStatus == .expiringSoon }
        case .expired:
            result = result.filter { $0.warrantyStatus == .expired }
        }

        // Category and tags
        if let selectedCategory {
            result = result.filter { $0.category?.caseInsensitiveCompare(selectedCategory) == .orderedSame }
        }

        if let selectedTag {
            result = result.filter { record in
                record.tags.contains { $0.caseInsensitiveCompare(selectedTag) == .orderedSame }
            }
        }

        // Purchase date
        switch dateFilterOption {
        case .any:
            break
        case .last30Days:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
            result = result.filter { ($0.purchaseDate ?? .distantPast) >= cutoff }
        case .thisYear:
            let year = Calendar.current.component(.year, from: .now)
            result = result.filter { record in
                guard let purchaseDate = record.purchaseDate else { return false }
                return Calendar.current.component(.year, from: purchaseDate) == year
            }
        case .noDate:
            result = result.filter { $0.purchaseDate == nil }
        }

        // Search (including OCR text in attachments)
        if !searchQuery.isEmpty {
            result = result.filter { record in
                record.productName.localizedCaseInsensitiveContains(searchQuery)
                || (record.merchantName?.localizedCaseInsensitiveContains(searchQuery) ?? false)
                || (record.notes?.localizedCaseInsensitiveContains(searchQuery) ?? false)
                || (record.category?.localizedCaseInsensitiveContains(searchQuery) ?? false)
                || record.tags.contains { $0.localizedCaseInsensitiveContains(searchQuery) }
                || attachments(for: record).contains { $0.ocrText?.localizedCaseInsensitiveContains(searchQuery) ?? false }
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

                LibraryFilterBar(
                    sortOption: $sortOption,
                    warrantyFilter: $filterOption,
                    dateFilter: $dateFilterOption,
                    selectedCategory: $selectedCategory,
                    selectedTag: $selectedTag,
                    availableCategories: availableCategories,
                    availableTags: availableTags,
                    activeFilterCount: activeFilterCount,
                    clearFilters: clearFilters
                )

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
                            description: Text("Try a different search or clear filters.")
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
                                PurchaseRecordCard(record: record, attachmentCount: attachments(for: record).count)
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
        let recordAttachments = attachments(for: record)
        let attachmentIDs = recordAttachments.map { $0.id }
        for attachment in recordAttachments {
            ImageStorageManager.delete(attachment.localFilename)
            modelContext.delete(attachment)
        }
        NotificationManager.shared.removeWarrantyReminders(for: record)
        modelContext.delete(record)

        // Clean up CloudKit image assets in background
        Task {
            for id in attachmentIDs {
                await cloudImageSync.delete(attachmentID: id)
            }
        }
    }

    private func clearFilters() {
        filterOption = .all
        dateFilterOption = .any
        selectedCategory = nil
        selectedTag = nil
    }

    private func sortedUnique(_ values: [String]) -> [String] {
        let trimmed = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return Array(Set(trimmed))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - Subviews

private struct LibraryFilterBar: View {
    @Binding var sortOption: LibrarySortOption
    @Binding var warrantyFilter: LibraryFilterOption
    @Binding var dateFilter: LibraryDateFilterOption
    @Binding var selectedCategory: String?
    @Binding var selectedTag: String?

    let availableCategories: [String]
    let availableTags: [String]
    let activeFilterCount: Int
    let clearFilters: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(LibrarySortOption.allCases, id: \.self) { option in
                        Button {
                            sortOption = option
                        } label: {
                            checkedLabel(option.rawValue, isSelected: sortOption == option)
                        }
                    }
                } label: {
                    FilterControlLabel(title: sortOption.rawValue, systemImage: "arrow.up.arrow.down")
                }

                Menu {
                    ForEach(LibraryFilterOption.allCases, id: \.self) { option in
                        Button {
                            warrantyFilter = option
                        } label: {
                            checkedLabel(option.rawValue, isSelected: warrantyFilter == option)
                        }
                    }
                } label: {
                    FilterControlLabel(title: warrantyFilter.rawValue, systemImage: "shield")
                }

                Menu {
                    ForEach(LibraryDateFilterOption.allCases, id: \.self) { option in
                        Button {
                            dateFilter = option
                        } label: {
                            checkedLabel(option.rawValue, isSelected: dateFilter == option)
                        }
                    }
                } label: {
                    FilterControlLabel(title: dateFilter.rawValue, systemImage: "calendar")
                }

                Menu {
                    Button {
                        selectedCategory = nil
                    } label: {
                        checkedLabel("Any Category", isSelected: selectedCategory == nil)
                    }

                    if !availableCategories.isEmpty {
                        Divider()
                    }

                    ForEach(availableCategories, id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            checkedLabel(category, isSelected: selectedCategory == category)
                        }
                    }
                } label: {
                    FilterControlLabel(title: selectedCategory ?? "Category", systemImage: "folder")
                }
                .disabled(availableCategories.isEmpty)

                Menu {
                    Button {
                        selectedTag = nil
                    } label: {
                        checkedLabel("Any Tag", isSelected: selectedTag == nil)
                    }

                    if !availableTags.isEmpty {
                        Divider()
                    }

                    ForEach(availableTags, id: \.self) { tag in
                        Button {
                            selectedTag = tag
                        } label: {
                            checkedLabel(tag, isSelected: selectedTag == tag)
                        }
                    }
                } label: {
                    FilterControlLabel(title: selectedTag ?? "Tag", systemImage: "tag")
                }
                .disabled(availableTags.isEmpty)

                if activeFilterCount > 0 {
                    Button(action: clearFilters) {
                        Label("Clear \(activeFilterCount)", systemImage: "xmark.circle.fill")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filters")
                }
            }
        }
    }

    @ViewBuilder
    private func checkedLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

private struct FilterControlLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemBackground), in: Capsule())
    }
}

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
    let attachmentCount: Int

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
                    AttachmentBadge(count: attachmentCount)

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
    .environmentObject(CloudImageSyncManager.shared)
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
