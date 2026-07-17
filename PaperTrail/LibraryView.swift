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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @State private var sortMode: LibrarySortMode = .newest
    /// v3 animPassV3 §9 #7 "Pull-to-refresh gold bookmark": live overscroll
    /// distance, read off the ScrollView via `LibraryScrollOffsetKey`, feeds
    /// `GoldBookmarkRibbon`. Always 0 (ribbon never drawn) when the flag is
    /// off or Reduce Motion is on.
    @State private var scrollOffset: CGFloat = 0

    private var householdCache = HouseholdCache.shared

    private func attachments(for record: PurchaseRecord) -> [Attachment] {
        allAttachments.filter { $0.recordID == record.id }
    }

    /// Add-sheet §2 "Photograph the thing": a record whose only image is the
    /// product photo (no receipt/warranty/invoice attached yet) reads as
    /// unproven — flag-gated and purely computed, no schema field.
    private func needsProof(_ record: PurchaseRecord) -> Bool {
        guard FeatureFlags.isOn(.addSheetV2) else { return false }
        let snapshot = NeedsProofSnapshot(
            productImageAttachmentID: record.productImageAttachmentID,
            otherAttachmentIDs: attachments(for: record)
                .filter { $0.id != record.productImageAttachmentID }
                .map(\.id)
        )
        return NeedsProofPredicate.needsProof(snapshot)
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

    // MARK: v3 passItOn (docs/design-v3/V3_BRIEF.md §7, flagged) — passed-on
    // exclusion. `activeRecords` feeds every value/count aggregation and the
    // normal Newest/A–Z/By room lists; `passedOnRecords` feeds the "Passed
    // on" shelf at the bottom. When the flag is off both collapse back to
    // v2 behavior exactly (`activeRecords == records`, `passedOnRecords` is
    // always empty) via `PassItOnAggregation.isExcludedFromAggregates`.

    private var activeRecords: [PurchaseRecord] {
        records.filter { !PassItOnAggregation.isExcludedFromAggregates(passedOnDate: $0.passedOnDate, flagOn: FeatureFlags.isOn(.passItOn)) }
    }

    private var passedOnRecords: [PurchaseRecord] {
        guard FeatureFlags.isOn(.passItOn) else { return [] }
        return records
            .filter { $0.passedOnDate != nil }
            .sorted { ($0.passedOnDate ?? .distantPast) > ($1.passedOnDate ?? .distantPast) }
    }

    private var attentionCount: Int {
        activeRecords.filter { $0.warrantyStatus == .expiringSoon || $0.warrantyStatus == .expired }.count
    }

    private var sortedRecords: [PurchaseRecord] {
        switch sortMode {
        case .newest:
            return activeRecords.sorted { $0.updatedAt > $1.updatedAt }
        case .az:
            return activeRecords.sorted { $0.productName.localizedCompare($1.productName) == .orderedAscending }
        case .byRoom:
            return activeRecords
        }
    }

    /// Grouped by room for the "By room" view. Records with no room fall under
    /// an "Unfiled" bucket sorted last — never forced to assign one.
    private var roomGroups: [(room: String, records: [PurchaseRecord])] {
        let grouped = Dictionary(grouping: activeRecords) { record -> String in
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
            // records behind "start your paper trail". Same reasoning
            // extends to a library that's ALL passed-on records — that's
            // still a library, just an empty active one.
            if activeRecords.isEmpty && !hasSharedRecords && passedOnRecords.isEmpty {
                EmptyLibraryView { router.showCapture = true }
            } else {
                content
            }
        }
        .ptScreen()
        .toolbar(.hidden, for: .navigationBar)
        // v3 animPassV3 §9 #7 "Pull-to-refresh gold bookmark": decorative
        // ribbon layered above the (unmodified) ScrollView/refreshable
        // content — see `content`'s doc comment for why it's decorative
        // rather than a full custom-refresh replacement. Absent entirely
        // off-flag/Reduce-Motion, so it can never intercept a touch
        // (`allowsHitTesting(false)` besides).
        .overlay(alignment: .top) {
            if AnimPass.isOn, !reduceMotion {
                GoldBookmarkRibbon(pull: scrollOffset)
                    .padding(.top, 2)
            }
        }
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

                if !passedOnRecords.isEmpty {
                    passedOnSection
                }
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.top, 8)
            .padding(.bottom, 120)
            .background {
                // v3 animPassV3 §9 #7: reports this content's Y offset inside
                // the ScrollView's own coordinate space, so `scrollOffset`
                // tracks live overscroll distance for `GoldBookmarkRibbon`.
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: LibraryScrollOffsetKey.self,
                        value: proxy.frame(in: .named("libraryScroll")).minY
                    )
                }
            }
        }
        .coordinateSpace(name: "libraryScroll")
        .onPreferenceChange(LibraryScrollOffsetKey.self) { scrollOffset = $0 }
        // v3 animPassV3 §9 #7: the system pull-to-refresh spinner
        // (`GoldBookmarkRibbon` above is a purely decorative layer on top of
        // it — a from-scratch custom refresh control fights `refreshable`'s
        // own gesture recognizer, so this keeps the reliable system
        // behavior and lets the ribbon be the "PaperTrail-flavored" part).
        // Refreshes the household roster, the one thing on this screen
        // ("Shared with me") that isn't already live off `@Query`.
        .libraryRefreshable(enabled: AnimPass.isOn) {
            await HouseholdManager.shared.refresh()
        }
        // v3 animPassV3 §9 #1 "Receipt prints on save": clears the
        // just-saved id once the entrance transition has had time to play,
        // so it never replays on a later Library visit. Keyed on the id
        // itself so a second save while this is still pending restarts the
        // hold rather than clearing early.
        .task(id: router.lastSavedRecordID) {
            guard router.lastSavedRecordID != nil else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            router.lastSavedRecordID = nil
        }
    }

    // MARK: v3 animPassV3 §9 #1/#2 (Receipt prints on save / shelving the card)

    /// The just-saved record gets a translateY-from-top entrance with a
    /// spring overshoot (the "receipt printing" moment); every other card
    /// just fades in as its neighbors part to make room — SwiftUI's own
    /// layout reflow under `libraryMotion` below does the "parting".
    /// Identity (`.identity`, no transition at all) off-flag, matching v2.
    private func cardTransition(for record: PurchaseRecord) -> AnyTransition {
        guard AnimPass.isOn else { return .identity }
        if reduceMotion { return .opacity }
        if record.id == router.lastSavedRecordID {
            return .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity)
        }
        return .opacity
    }

    /// Drives both #1's entrance and #2's neighbor-parting reflow off one
    /// shared spring — a single `.animation(value:)` on `sortedRecords`'
    /// identity list, so a new/removed/reordered record animates in one
    /// consistent motion rather than each row picking its own curve.
    private var libraryMotion: Animation? {
        guard AnimPass.isOn else { return nil }
        return AnimPass.animation(
            .interpolatingSpring(mass: 0.6, stiffness: 170, damping: 15),
            reduceMotion: reduceMotion
        )
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
                    RecordFilingCard(record: record, needsProof: needsProof(record))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", role: .destructive) { deleteRecord(record) }
                }
                .transition(cardTransition(for: record))
            }
        }
        .animation(libraryMotion, value: sortedRecords.map(\.id))
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

    // MARK: Passed on (docs/design-v3/V3_BRIEF.md §7)

    private var passedOnSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionLabel(text: "Passed on", tone: PT.txt3)
                Text("\(passedOnRecords.count)")
                    .font(PTFont.mono(10))
                    .foregroundStyle(PT.txt3)
                GoldRule()
            }
            VStack(spacing: 0) {
                ForEach(passedOnRecords) { record in
                    NavigationLink {
                        RecordDetailView(record: record)
                    } label: {
                        PassedOnRow(record: record)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", role: .destructive) { deleteRecord(record) }
                    }
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
        // v3 multiCoverage (§3): same remove-on-delete path as the warranty/
        // return-window reminders above. Unconditional — a record deleted
        // after the flag was turned off could still have coverage-line
        // reminders scheduled from when the flag was on, and those would
        // otherwise leak forever (§6 coverage reminders discipline).
        let recordID = record.id
        Task { await CoverageReminders.removeReminders(for: recordID) }
        SpotlightIndexer.deindex(recordID: record.id)
        // v3 manualOnFile (§5): local-only store, not part of the SwiftData
        // graph — needs its own explicit cleanup here, same as
        // `RecordDetailView.deleteRecord`. No-op if no manual was attached.
        ManualStore.delete(for: record.id)
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
    var needsProof: Bool = false

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
                    Text(record.displayProductName)
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
                // BUILD_REVIEW B3: this card is cream — pills use the deep
                // on-paper tones, not the dark-background palette.
                if needsProof {
                    TonedStatusPill(text: "Add proof", tone: PT.amber, textColor: Color(hex: 0x8A6420), background: Color(hex: 0xD7A64C, alpha: 0.18))
                }
                if record.warrantyExpiryDate != nil {
                    StatusPill(status: warranty.status, text: warranty.pillText, onPaper: true)
                }
                if let badgeText = returnWindow.badgeText {
                    TonedStatusPill(text: badgeText, tone: returnWindow.tone, textColor: Color(hex: 0x8A6420), background: Color(hex: 0xD7A64C, alpha: 0.18))
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
        if let merchant = record.displayMerchantName, !merchant.isEmpty { parts.append(merchant) }
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
                Text(record.displayProductName)
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
                Text(PTDisplayName.product(record.productName))
                    .font(PTFont.serif(16, weight: 500))
                    .foregroundStyle(PT.txt)
                    .lineLimit(1)
                Text(record.merchantName.map(PTDisplayName.merchant) ?? "Shared item")
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

// MARK: - Passed-on row ("Passed on" shelf)

/// Row for a record marked passed-on (docs/design-v3/V3_BRIEF.md §7) —
/// styled after `RoomRow`, with a mono "SOLD · PASSED ON" stamp in place of
/// the warranty dot. Tapping still opens the full detail view, where "Mark
/// as not passed on" lives.
private struct PassedOnRow: View {
    let record: PurchaseRecord
    private var warranty: PTWarranty { PTWarranty(record: record) }

    var body: some View {
        HStack(spacing: 12) {
            GlyphTile(symbol: warranty.glyph, size: 34)
                .opacity(0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayProductName)
                    .font(PTFont.serif(16, weight: 500))
                    .foregroundStyle(PT.txt2)
                    .lineLimit(1)
                if let passedOnDate = record.passedOnDate {
                    Text("Passed on \(PTDate.dayMonthYear.string(from: passedOnDate))")
                        .font(PTFont.mono(10))
                        .foregroundStyle(PT.txt3)
                }
            }
            Spacer(minLength: 8)
            Text("SOLD · PASSED ON")
                .font(PTFont.mono(9, medium: true))
                .tracking(1)
                .foregroundStyle(PT.txt3)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(PT.hair, lineWidth: 1))
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
