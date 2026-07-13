import SwiftUI

/// Read-only detail for a record shared *to* this device (Milestone 4 Phase 3
/// — see docs/SHARING_ARCHITECTURE.md). Renders a `SharedPurchaseRecordDTO`
/// straight from `HouseholdCache`, never a SwiftData `PurchaseRecord` — this
/// view must never be reachable for locally-owned records, and it must never
/// feed a DTO into `EditRecordView` (members are read-only in v1). Images
/// aren't mirrored yet (Phase 4); attachments show as metadata rows only.
struct SharedRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss

    /// The record as handed in when navigating here (e.g. from the Library's
    /// "Shared with me" row). `current` re-reads the cache by id in `body` so
    /// live sync updates (an edit made on another device) render without
    /// re-navigating.
    let record: SharedPurchaseRecordDTO

    private var householdCache = HouseholdCache.shared

    // Explicit init: the private householdCache stored property would
    // otherwise demote the synthesized memberwise init to private, making
    // the view unconstructible from LibraryView.
    init(record: SharedPurchaseRecordDTO) {
        self.record = record
    }

    private var current: SharedPurchaseRecordDTO {
        householdCache.purchaseRecord(id: record.id) ?? record
    }

    private var attachments: [SharedAttachmentDTO] {
        householdCache.attachments(forRecordID: record.id)
    }

    private var warrantyStatus: WarrantyStatus {
        guard let expiry = current.warrantyExpiryDate else { return .unknown }
        if expiry < .now { return .expired }
        let cutoff = Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now
        return expiry <= cutoff ? .expiringSoon : .active
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sharedBadge

                heroCard

                detailsCard

                if current.warrantyExpiryDate != nil {
                    warrantyBlock
                }

                proofSection

                if hasSupportInfo {
                    supportCard
                }

                if let notes = current.notes, !notes.isEmpty {
                    notesCard(notes)
                }
            }
            .padding(.horizontal, PT.Metric.detailPad)
            .padding(.bottom, 120)
        }
        .ptScreen()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
    }

    // MARK: Shared badge

    private var sharedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "house.fill")
                .font(.system(size: 10.5))
            Text("Shared by your household")
                .font(PTFont.mono(10.5, medium: true))
                .tracking(1.2)
                .textCase(.uppercase)
        }
        .foregroundStyle(PT.gold)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color(hex: 0xD7A64C, alpha: 0.1), in: Capsule())
        .overlay(Capsule().stroke(PT.gold.opacity(0.3), lineWidth: 1))
        .padding(.top, 8)
    }

    // MARK: Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                GlyphTile(symbol: ptGlyph(category: current.category, productName: current.productName), size: 52, onPaper: true)
                Spacer()
                StampBadge(text: warrantyStampText, tone: warrantyStatus.tone)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(current.productName)
                    .font(PTFont.serif(26, weight: 600))
                    .foregroundStyle(PT.onPaper)
                    .lineLimit(3)
                if let meta = metaLine {
                    Text(meta)
                        .font(PTFont.mono(11))
                        .tracking(0.6)
                        .foregroundStyle(PT.onPaper3)
                }
            }

            Rectangle().fill(PT.onPaperHair).frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                heroStat(label: "Paid", value: current.formattedAmount ?? "—", mono: true)
                heroStat(label: "From", value: current.merchantName ?? "—", mono: false)
                heroStat(label: "Bought", value: current.purchaseDate.map { PTDate.dayMonthYear.string(from: $0) } ?? "—", mono: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: true)
    }

    private var metaLine: String? {
        var parts: [String] = []
        if let category = current.category, !category.isEmpty { parts.append(category) }
        if let room = current.room, !room.isEmpty { parts.append(room) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func heroStat(label: String, value: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .ptMonoLabel(8.5, tracking: 1.5)
                .foregroundStyle(PT.onPaper3)
            Text(value)
                .font(mono ? PTFont.mono(13, medium: true) : PTFont.serif(15, weight: 500))
                .foregroundStyle(PT.onPaper)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Details card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Details", tone: PT.txt3)

            detailRow(label: "Model", value: current.productName)

            if let serial = current.serialNumber, !serial.isEmpty {
                detailRow(label: "Serial no.", value: serial, mono: true)
            }

            if let coverage = current.coverageSummary, !coverage.isEmpty {
                detailRow(label: "Covers", value: coverage)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xE7DCC4, alpha: 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }

    private func detailRow(label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(PT.txt3)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? PTFont.mono(13, medium: true) : PTFont.serif(15, weight: 500))
                .foregroundStyle(PT.txt)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Warranty block

    private var warrantyBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Warranty", tone: warrantyStatus.tone)
            Text(warrantyPillText)
                .font(PTFont.serif(20, weight: 600, italic: true))
                .foregroundStyle(PT.txt)
            HStack {
                Text("\(current.purchaseDate.map { PTDate.dayMonthYear.string(from: $0) } ?? "—") — purchased")
                    .font(PTFont.mono(10))
                    .foregroundStyle(PT.txt3)
                Spacer()
                Text("\(current.warrantyExpiryDate.map { PTDate.dayMonthYear.string(from: $0) } ?? "—") — \(warrantyStatus == .expired ? "expired" : "expires")")
                    .font(PTFont.mono(10))
                    .foregroundStyle(PT.txt3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(warrantyStatus.tone.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(warrantyStatus.tone.opacity(0.25), lineWidth: 1))
    }

    private var warrantyStampText: String {
        switch warrantyStatus {
        case .active: "Under warranty"
        case .expiringSoon: "Expiring"
        case .expired: "Out of warranty"
        case .unknown: "No warranty"
        }
    }

    private var warrantyPillText: String {
        switch warrantyStatus {
        case .expired:
            "Expired"
        case .expiringSoon:
            current.warrantyExpiryDate.map { "Expires in \(PTWarranty.relativeFuture($0))" } ?? "Expiring soon"
        case .active:
            current.warrantyExpiryDate.map { "Covered · \(PTWarranty.relativeFuture($0)) left" } ?? "Covered"
        case .unknown:
            "No warranty"
        }
    }

    // MARK: Proof (metadata only — Phase 4 adds images)

    private var proofSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Proof on file", tone: PT.txt3)
                Spacer()
                if !attachments.isEmpty {
                    Text("\(attachments.count) document\(attachments.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(PT.txt3)
                }
            }

            if attachments.isEmpty {
                Text("No proof documents shared for this item yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(PT.txt3)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                        if index > 0 { Rectangle().fill(PT.hair).frame(height: 1) }
                        HStack(spacing: 10) {
                            Image(systemName: proofGlyph(attachment.typeRaw))
                                .font(.system(size: 13))
                                .foregroundStyle(PT.gold)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(proofLabel(attachment.typeRaw))
                                    .font(.system(size: 13))
                                    .foregroundStyle(PT.txt)
                                Text(attachment.localFilename)
                                    .font(PTFont.mono(10))
                                    .foregroundStyle(PT.txt3)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(.vertical, 9)
                    }
                }

                Text("Images sync arrives in a later update.")
                    .font(.system(size: 11))
                    .foregroundStyle(PT.txt3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xE7DCC4, alpha: 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }

    private func proofGlyph(_ typeRaw: String) -> String {
        switch AttachmentType(rawValue: typeRaw) ?? .other {
        case .receipt: "receipt"
        case .warranty: "shield.lefthalf.filled"
        case .invoice: "doc.text"
        case .other: "doc"
        }
    }

    private func proofLabel(_ typeRaw: String) -> String {
        switch AttachmentType(rawValue: typeRaw) ?? .other {
        case .receipt: "Receipt"
        case .warranty: "Warranty card"
        case .invoice: "Invoice"
        case .other: "Document"
        }
    }

    // MARK: Support card

    private var hasSupportInfo: Bool {
        current.supportProviderName != nil || current.supportPhoneNumber != nil
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "If it breaks", tone: PT.onPaper3)
            if let name = current.supportProviderName {
                Text(name)
                    .font(PTFont.serif(18, weight: 600))
                    .foregroundStyle(PT.onPaper)
            }
            if let phone = current.supportPhoneNumber {
                Text(phone)
                    .font(PTFont.mono(13, medium: true))
                    .foregroundStyle(PT.onPaper2)
            }
            if current.supportConfidence == "verified" {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 11))
                    Text("Verified from the owner's receipt").font(PTFont.mono(10))
                }
                .foregroundStyle(PT.sageDeep)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: false)
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Notes", tone: PT.txt3)
            Text(notes)
                .font(.system(size: 14))
                .foregroundStyle(PT.txt)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xE7DCC4, alpha: 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }
}

// MARK: - DTO display helpers (deliberately duplicated, not touching PurchaseRecord)

private extension SharedPurchaseRecordDTO {
    /// Mirrors `PurchaseRecord.formattedAmount` — kept as a minimal duplicate
    /// here rather than reused from the model, per the DTO/model boundary
    /// (never render SwiftData models from cache DTOs or vice versa).
    var formattedAmount: String? {
        guard let amount else { return nil }
        let cur = currency ?? "SGD"
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = cur
        return formatter.string(from: NSNumber(value: amount))
    }
}
