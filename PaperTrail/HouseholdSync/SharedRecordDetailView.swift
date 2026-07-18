import SwiftUI

/// Read-only detail for a record shared *to* this device (Milestone 4 Phase 3
/// — see docs/SHARING_ARCHITECTURE.md). Renders a `SharedPurchaseRecordDTO`
/// straight from `HouseholdCache`, never a SwiftData `PurchaseRecord` — this
/// view must never be reachable for locally-owned records, and it must never
/// feed a DTO into `EditRecordView` (members are read-only in v1). Attachment
/// images (Phase 4) are read from `HouseholdCache.imageURL(attachmentID:)`
/// when present; an attachment whose asset hasn't arrived yet falls back to
/// a "syncing" placeholder rather than blocking the rest of the view.
struct SharedRecordDetailView: View {
    @Environment(\.dismiss) private var dismiss

    /// The record as handed in when navigating here (e.g. from the Library's
    /// "Shared with me" row). `current` re-reads the cache by id in `body` so
    /// live sync updates (an edit made on another device) render without
    /// re-navigating.
    let record: SharedPurchaseRecordDTO

    @State private var zoomedProof: ZoomedProofImage?

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
        .fullScreenCover(item: $zoomedProof) { proof in
            SharedProofViewerView(image: proof.image)
        }
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

    // MARK: Proof (images ride as a CKAsset on SharedAttachment — Phase 4)

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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(attachments) { attachment in
                            VStack(spacing: 8) {
                                // Tap-to-enlarge only once the asset is on
                                // disk — the "syncing" placeholder isn't a
                                // button.
                                Button {
                                    if let url = HouseholdCache.shared.imageURL(attachmentID: attachment.id),
                                       let image = UIImage(contentsOfFile: url.path) {
                                        zoomedProof = ZoomedProofImage(id: attachment.id, image: image)
                                    }
                                } label: {
                                    SharedProofThumbnail(attachment: attachment)
                                }
                                .buttonStyle(.plain)
                                HStack(spacing: 5) {
                                    Image(systemName: proofGlyph(attachment.typeRaw))
                                        .font(.system(size: 10))
                                        .foregroundStyle(PT.gold)
                                    Text(proofLabel(attachment.typeRaw))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(PT.txt2)
                                }
                            }
                        }
                    }
                }
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
        let cur = currency ?? PTCurrency.deviceDefault
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = cur
        return formatter.string(from: NSNumber(value: amount))
    }
}

// MARK: - Shared proof thumbnail

/// Styled like `RecordDetailView`'s (private) `ProofThumbnail` — same frame,
/// dog-ear clip, and hairline border — but reads from `HouseholdCache`'s
/// images directory instead of `ImageStorageManager`'s, since this attachment
/// was never saved into this device's own Documents/Attachments. Tap-to-
/// enlarge goes through `SharedProofViewerView` (the UIImage is handed over
/// directly) rather than `ImageViewerView`, which loads by filename via
/// `ImageStorageManager`/`CloudImageSyncManager` and knows nothing about
/// shared-in attachments.
private struct SharedProofThumbnail: View {
    let attachment: SharedAttachmentDTO

    private var image: UIImage? {
        guard let url = HouseholdCache.shared.imageURL(attachmentID: attachment.id) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    PT.inkRaised
                    VStack(spacing: 4) {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 16))
                        Text("Image syncing…")
                            .font(.system(size: 8))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(PT.txt3)
                    .padding(.horizontal, 6)
                }
            }
        }
        .frame(width: 78, height: 104)
        .clipShape(DogEarShape(radius: 10, ear: 14))
        .overlay(DogEarShape(radius: 10, ear: 14).stroke(PT.hair, lineWidth: 1))
    }
}

// MARK: - Shared proof viewer

/// `Identifiable` payload for `.fullScreenCover(item:)` — the attachment id
/// keys the cover, the `UIImage` is already loaded by the tap handler.
private struct ZoomedProofImage: Identifiable {
    let id: UUID
    let image: UIImage
}

/// Full-screen zoomable viewer for a shared-in proof image. Mirrors
/// `ImageViewerView`'s gestures (pinch + double-tap zoom) but takes the
/// `UIImage` directly — no filename lookup, no iCloud download path; the
/// image is guaranteed on disk before this is ever presented.
private struct SharedProofViewerView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = value.magnification
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.3)) {
                                    scale = max(1.0, scale)
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3)) {
                            scale = scale > 1.0 ? 1.0 : 2.5
                        }
                    }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
