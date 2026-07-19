import SwiftUI
import SwiftData

struct SearchView: View {
    @Query(sort: \PurchaseRecord.updatedAt, order: .reverse) private var records: [PurchaseRecord]
    @Query private var allAttachments: [Attachment]
    @FocusState private var searchFocused: Bool
    @State private var searchText = ""
    private var householdCache = HouseholdCache.shared

    private func attachments(for record: PurchaseRecord) -> [Attachment] {
        allAttachments.filter { $0.recordID == record.id }
    }

    private var results: [PurchaseRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return records.filter { Self.matches(record: $0, attachments: attachments(for: $0), query: query) }
    }

    /// Shared-in household records matching the query — the household's stuff
    /// is findable from a member phone too (same derivation as LibraryView's
    /// "Shared with me": cache DTOs minus anything that exists locally).
    private var sharedResults: [SharedPurchaseRecordDTO] {
        guard HouseholdManager.recordSharingEnabled else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return householdCache.purchaseRecords.filter { dto in
            !records.contains(where: { $0.id == dto.id }) && Self.matchesShared(dto: dto, query: query)
        }
    }

    /// Whether `record` matches `query` (case-insensitive substring match, so a
    /// partial serial number — e.g. the last few characters typed off a barcode
    /// scan — still matches). Static + pure so it's unit-testable without a
    /// live `@Query`.
    static func matches(record: PurchaseRecord, attachments: [Attachment], query: String) -> Bool {
        record.productName.localizedCaseInsensitiveContains(query)
        || (record.merchantName?.localizedCaseInsensitiveContains(query) ?? false)
        || (record.notes?.localizedCaseInsensitiveContains(query) ?? false)
        || (record.category?.localizedCaseInsensitiveContains(query) ?? false)
        || (record.room?.localizedCaseInsensitiveContains(query) ?? false)
        || (record.serialNumber?.localizedCaseInsensitiveContains(query) ?? false)
        || record.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        || attachments.contains { $0.ocrText?.localizedCaseInsensitiveContains(query) ?? false }
    }

    /// Shared-DTO variant of `matches` — same fields where the wire carries
    /// them (no attachment OCR: shared proof text isn't mirrored). Static +
    /// pure for the same testability reason.
    static func matchesShared(dto: SharedPurchaseRecordDTO, query: String) -> Bool {
        dto.productName.localizedCaseInsensitiveContains(query)
        || (dto.merchantName?.localizedCaseInsensitiveContains(query) ?? false)
        || (dto.notes?.localizedCaseInsensitiveContains(query) ?? false)
        || (dto.category?.localizedCaseInsensitiveContains(query) ?? false)
        || (dto.room?.localizedCaseInsensitiveContains(query) ?? false)
        || (dto.serialNumber?.localizedCaseInsensitiveContains(query) ?? false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Search")
                    .font(PTFont.serif(34, weight: 600))
                    .foregroundStyle(PT.txt)
                    .padding(.top, 8)

                searchField

                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hint
                } else if results.isEmpty && sharedResults.isEmpty {
                    emptyResults
                } else {
                    VStack(spacing: PT.Metric.cardGap) {
                        ForEach(results) { record in
                            NavigationLink {
                                RecordDetailView(record: record)
                            } label: {
                                RecordFilingCard(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !sharedResults.isEmpty {
                        HStack(spacing: 8) {
                            SectionLabel(text: "From your household", tone: PT.gold)
                            GoldRule()
                        }
                        .padding(.top, results.isEmpty ? 0 : 6)
                        VStack(spacing: PT.Metric.cardGap) {
                            ForEach(sharedResults) { dto in
                                NavigationLink {
                                    SharedRecordDetailView(record: dto)
                                } label: {
                                    SharedFilingCard(record: dto)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.bottom, 120)
        }
        .ptScreen()
        .toolbar(.hidden, for: .navigationBar)
        .ptKeyboardDoneToolbar()
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(PT.txt3)
            TextField("", text: $searchText, prompt: Text("Products, stores, receipt text, tags").foregroundStyle(PT.txt3))
                .font(.system(size: 15))
                .foregroundStyle(PT.txt)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(PT.txt3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(hex: 0xE7DCC4, alpha: 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(searchFocused ? PT.goldDeep : PT.hair, lineWidth: 1))
    }

    private var hint: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(PT.txt3)
            Text("Search across everything you own —\neven the text inside your scanned receipts.")
                .font(.system(size: 13))
                .foregroundStyle(PT.txt3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var emptyResults: some View {
        VStack(spacing: 8) {
            Text("No matches")
                .font(PTFont.serif(20, weight: 600))
                .foregroundStyle(PT.txt2)
            Text("Try a different word or check the spelling.")
                .font(.system(size: 13))
                .foregroundStyle(PT.txt3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }
}

#Preview {
    NavigationStack { SearchView() }
        .environmentObject(CloudImageSyncManager.shared)
        .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
