import SwiftUI
import SwiftData

enum LibrarySortMode: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case byRoom = "By room"
    case az = "A–Z"
    var id: String { rawValue }
}

struct LibraryView: View {
    @Query(sort: \PurchaseRecord.updatedAt, order: .reverse) private var records: [PurchaseRecord]
    @Query private var allAttachments: [Attachment]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @State private var sortMode: LibrarySortMode = .newest

    private var householdCache = HouseholdCache.shared

    private func attachments(for record: PurchaseRecord) -> [Attachment] {
        allAttachments.filter { $0.recordID == record.id }
    }

    /// Records mirrored *to* this device by another household member — cache
    /// DTOs with no matching local `PurchaseRecord`. Excludes the owner's own
    /// mirrors (those DO have a local record) so this only ever shows what a
    /// MEMBER sees from the owner.
    private var sharedWithMe: [SharedPurchaseRecordDTO] {
        householdCache.purchaseRecords.filter { dto in !records.contains(where: { $0.id == dto.id }) }
    }

    private var hasSharedRecords: Bool {
        HouseholdManager.recordSharingEnabled && !sharedWithMe.isEmpty
    }

    private var attentionCount: Int {
        records.filter { $0.warrantyStatus == .expiringSoon || $0.warrantyStatus == .expired }.count
    }

    private var sortedRecords: [PurchaseRecord] {
        switch sortMode {
        case .newest:
            return records.sorted { $0.updatedAt > $1.updatedAt }
        case .az:
            return records.sorted { $0.productName.localizedCompare($1.productName) == .orderedAscending }
        case .byRoom:
            return records
        }
    }

    /// Grouped by room for the "By room" view. Records with no room fall under
    /// an "Unfiled" bucket sorted last — never forced to assign one.
    private var roomGroups: [(room: String, records: [PurchaseRecord])] {
        let grouped = Dictionary(grouping: records) { record -> String in
            let trimmed = record.room?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty ?? true) ? "Unfiled" : trimmed!
        }
        return grouped
            .map { (room: $0.key, records: $0.value.sorted { $0.productName.localizedCompare($1.productName) == .orderedAscending }) }
            .sorted { lhs, rhs in
                if lhs.room == "Unfiled" { return false }
                if rhs.room == "Unfiled" { return true }
                return lhs.room.localizedCompare(rhs.room) == .orderedAscending
            }
    }

    var body: some View {
        Group {
            // A household member with no records of their own still has a
            // library to show — the empty state hid Vanessa's 5 shared-in
            // records behind "start your paper trail".
            if records.isEmpty && !hasSharedRecords {
                EmptyLibraryView { router.showCapture = true }
            } else {
                content
            }
        }
        .ptScreen()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Text("The Library")
                    .font(PTFont.serif(34, weight: 600))
                    .foregroundStyle(PT.txt)
                    .padding(.top, 2)

                searchField

                segmentedSort

                if attentionCount > 0 {
                    AttentionBanner(count: attentionCount) {
                        router.selectedTab = .warranty
                    }
                }

                if hasSharedRecords {
                    sharedWithMeSection
                }

                if sortMode == .byRoom {
                    roomList
                } else {
                    flatList
                }
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("PaperTrail").ptWordmark()
            Spacer()
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        Button {
            router.selectedTab = .search
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                Text("Search your library")
                    .font(.system(size: 14))
                Spacer()
            }
            .foregroundStyle(PT.txt3)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(hex: 0xE7DCC4, alpha: 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PT.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var segmentedSort: some View {
        HStack(spacing: 4) {
            ForEach(LibrarySortMode.allCases) { mode in
                let isActive = sortMode == mode
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { sortMode = mode }
                } label: {
                    Text(mode.rawValue)
                        .font(PTFont.mono(10.5, medium: isActive))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(isActive ? PT.inkStamp : PT.txt2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if isActive {
                                RoundedRectangle(cornerRadius: PT.Metric.pillRadius - 2, style: .continuous)
                                    .fill(LinearGradient(colors: [PT.goldHi, PT.gold], startPoint: .top, endPoint: .bottom))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(hex: 0xE7DCC4, alpha: 0.05), in: RoundedRectangle(cornerRadius: PT.Metric.pillRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PT.Metric.pillRadius, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }

    // MARK: Lists

    private var flatList: some View {
        VStack(spacing: PT.Metric.cardGap) {
            ForEach(sortedRecords) { record in
                NavigationLink {
                    RecordDetailView(record: record)
                } label: {
                    RecordFilingCard(record: record)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", role: .destructive) { deleteRecord(record) }
                }
            }
        }
    }

    private var roomList: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(roomGroups, id: \.room) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        SectionLabel(text: group.room, tone: PT.gold)
                        Text("\(group.records.count)")
                            .font(PTFont.mono(10))
                            .foregroundStyle(PT.txt3)
                        GoldRule()
                    }
                    ForEach(group.records) { record in
                        NavigationLink {
                            RecordDetailView(record: record)
                        } label: {
                            RoomRow(record: record)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", role: .destructive) { deleteRecord(record) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Shared with me

    private var sharedWithMeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionLabel(text: "Shared with me", tone: PT.gold)
                Text("\(sharedWithMe.count)")
                    .font(PTFont.mono(10))
                    .foregroundStyle(PT.txt3)
                GoldRule()
            }
            VStack(spacing: 0) {
                ForEach(sharedWithMe) { dto in
                    NavigationLink {
                        SharedRecordDetailView(record: dto)
                    } label: {
                        SharedRecordRow(record: dto)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func deleteRecord(_ record: PurchaseRecord) {
        let recordAttachments = attachments(for: record)
        let attachmentIDs = recordAttachments.map { $0.id }
        for attachment in recordAttachments {
            ImageStorageManager.delete(attachment.localFilename)
            modelContext.delete(attachment)
        }
        NotificationManager.shared.removeWarrantyReminders(for: record)
        NotificationManager.shared.removeReturnWindowReminder(for: record)
        modelContext.delete(record)

        // Fix 1: deletion requires positive evidence, and this IS that
        // evidence — unshare/purge the household mirror here rather than
        // letting a reconcile diff infer it from local absence (see
        // docs/SHARING_ARCHITECTURE.md). No-op when record sharing is off.
        HouseholdMirrorCoordinator.shared.recordDeleted(recordID: record.id, attachmentIDs: attachmentIDs)

        Task {
            for id in attachmentIDs {
                await cloudImageSync.delete(attachmentID: id)
            }
        }
    }
}

// MARK: - Filing card (Newest / A–Z)

struct RecordFilingCard: View {
    let record: PurchaseRecord

    private var warranty: PTWarranty { PTWarranty(record: record) }
    private var returnWindow: PTReturnWindow { PTReturnWindow(record: record) }

    private var metaLine: String {
        var parts: [String] = []
        if let category = record.category, !category.isEmpty { parts.append(category) }
        if let date = record.purchaseDate { parts.append(PTDate.monthYear.string(from: date)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                GlyphTile(symbol: warranty.glyph, size: 38, onPaper: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.productName)
                        .font(PTFont.serif(18, weight: 600))
                        .foregroundStyle(PT.onPaper)
                        .lineLimit(2)
                    if !metaLine.isEmpty {
                        Text(metaLine)
                            .font(PTFont.mono(10.5))
                            .tracking(0.6)
                            .foregroundStyle(PT.onPaper3)
                    }
                }
                Spacer(minLength: 0)
            }

            Rectangle().fill(PT.onPaperHair).frame(height: 1)

            HStack(spacing: 8) {
                Text(priceMerchant)
                    .font(PTFont.mono(11.5, medium: true))
                    .foregroundStyle(PT.onPaper2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if record.warrantyExpiryDate != nil {
                    StatusPill(status: warranty.status, text: warranty.pillText)
                }
                if let badgeText = returnWindow.badgeText {
                    TonedStatusPill(text: badgeText, tone: returnWindow.tone, textColor: returnWindow.textColor, background: returnWindow.background)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: true)
    }

    private var priceMerchant: String {
        var parts: [String] = []
        if let amount = record.formattedAmount { parts.append(amount) }
        if let merchant = record.merchantName, !merchant.isEmpty { parts.append(merchant) }
        return parts.isEmpty ? "—" : parts.joined(separator: "  ·  ")
    }
}

// MARK: - Room row (By room)

private struct RoomRow: View {
    let record: PurchaseRecord
    private var warranty: PTWarranty { PTWarranty(record: record) }
    private var returnWindow: PTReturnWindow { PTReturnWindow(record: record) }

    var body: some View {
        HStack(spacing: 12) {
            GlyphTile(symbol: warranty.glyph, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.productName)
                    .font(PTFont.serif(16, weight: 500))
                    .foregroundStyle(PT.txt)
                    .lineLimit(1)
                Text(record.warrantyExpiryDate != nil ? warranty.pillText : "No warranty")
                    .font(PTFont.mono(10))
                    .foregroundStyle(PT.txt3)
            }
            Spacer(minLength: 8)
            if record.warrantyExpiryDate != nil {
                Circle().fill(warranty.status.tone).frame(width: 7, height: 7)
            }
            if returnWindow.status.isClosingSoon {
                Circle().fill(returnWindow.tone).frame(width: 7, height: 7)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PT.txt3)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(PT.hair).frame(height: 1)
        }
    }
}

// MARK: - Shared record row ("Shared with me")

/// Row for a record mirrored in from another household member — styled after
/// `RoomRow`, but reads a `SharedPurchaseRecordDTO` (never a `PurchaseRecord`)
/// and swaps the trailing chevron area for a household glyph so it reads as
/// distinct from the owner's own records.
private struct SharedRecordRow: View {
    let record: SharedPurchaseRecordDTO

    private var glyph: String { ptGlyph(category: record.category, productName: record.productName) }

    var body: some View {
        HStack(spacing: 12) {
            GlyphTile(symbol: glyph, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.productName)
                    .font(PTFont.serif(16, weight: 500))
                    .foregroundStyle(PT.txt)
                    .lineLimit(1)
                Text(record.merchantName ?? "Shared item")
                    .font(PTFont.mono(10))
                    .foregroundStyle(PT.txt3)
            }
            Spacer(minLength: 8)
            Image(systemName: "house.fill")
                .font(.system(size: 11))
                .foregroundStyle(PT.gold)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PT.txt3)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(PT.hair).frame(height: 1)
        }
    }
}

#Preview {
    AppShellView()
        .environmentObject(CloudImageSyncManager.shared)
        .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
