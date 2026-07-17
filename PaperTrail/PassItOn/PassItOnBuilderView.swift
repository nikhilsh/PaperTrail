import SwiftUI
import SwiftData
import PDFKit

/// "Pass it on" buyer-packet builder (docs/design-v3/V3_BRIEF.md §7, V3-1
/// mock): a paper checklist of pages that assembles live into a PDF for the
/// next owner. Reached from `RecordDetailView.passItOnRow`.
struct PassItOnBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allAttachments: [Attachment]
    @Bindable var record: PurchaseRecord

    @State private var selection = PassItOnPacket.Selection()
    @State private var manualRecord: ManualRecord?
    @State private var isGenerating = false
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    /// Set once a packet has actually been shared this session — "Mark as
    /// passed on" only appears after the handover, matching the mock's
    /// footnote ("Sharing doesn't remove the item — mark it 'passed on'
    /// after the sale").
    @State private var hasShared = false
    @State private var toast: PTToastItem?
    // v3 animPassV3 §9 #6 "Pass-it-on handover": true once the user has
    // actually confirmed "Mark as passed on" — see `markPassedOnRow`.
    // **Delta from the brief**: Ideas.html anchors this to "on share
    // completion", but sharing alone doesn't change `record.passedOnDate`
    // (this screen's own footnote says so: "Sharing doesn't remove the item
    // — mark it passed on after the sale"). Firing the SOLD·PASSED ON stamp
    // at share time would visually claim a state the record isn't actually
    // in yet. Anchoring to the real state-changing tap instead keeps the
    // animation honest about what just happened.
    @State private var showHandoverStamp = false
    private var animPassOn: Bool { AnimPass.isOn }

    // MARK: Availability

    /// Non-photo attachments actually on file — the product photo isn't
    /// proof of purchase, same distinction `RecordDetailView.documentAttachments`
    /// draws. See `PassItOnPacket.hasProofOfPurchase` for the pure predicate
    /// and why this replaced a hardcoded `true` stub (item 2, HIGH).
    private var hasProofOfPurchase: Bool {
        PassItOnPacket.hasProofOfPurchase(
            attachmentIDs: allAttachments.filter { $0.recordID == record.id }.map(\.id),
            productImageAttachmentID: record.productImageAttachmentID
        )
    }

    private var hasRemainingWarranty: Bool {
        guard let expiry = record.warrantyExpiryDate else { return false }
        return expiry > .now
    }

    private var hasServiceHistory: Bool { !record.serviceEntries.isEmpty }

    private var manualPageCount: Int {
        guard let url = ManualStore.url(for: record.id), let doc = CGPDFDocument(url as CFURL) else { return 1 }
        return max(doc.numberOfPages, 1)
    }

    private var availability: PassItOnPacket.Availability {
        PassItOnPacket.Availability(
            hasProofOfPurchase: hasProofOfPurchase,
            hasRemainingWarranty: hasRemainingWarranty,
            hasServiceHistory: hasServiceHistory,
            hasManual: manualRecord != nil,
            manualPageCount: manualPageCount
        )
    }

    private var pageCount: Int { PassItOnPacket.pageCount(selection: selection, availability: availability) }

    /// Rough live estimate — a flat per-page allowance for the text
    /// sections plus the manual's real on-disk size when included. Not
    /// meant to match the rendered PDF byte-for-byte, just to move
    /// believably as the user toggles pages, matching the V3-1 mock's live
    /// "2.1 MB" row.
    private var estimatedSizeText: String {
        var bytes = 60_000 // cover
        if selection.includeProofOfPurchase && availability.hasProofOfPurchase { bytes += 70_000 }
        if selection.includeRemainingWarranty && availability.hasRemainingWarranty { bytes += 50_000 }
        if selection.includeServiceHistory && availability.hasServiceHistory { bytes += 60_000 }
        if selection.includeManual, let manualRecord { bytes += manualRecord.byteCount }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var monthsRemainingText: String {
        guard let expiry = record.warrantyExpiryDate else { return "" }
        let months = max(0, Calendar.current.dateComponents([.month], from: .now, to: expiry).month ?? 0)
        return months == 1 ? "1 mo" : "\(months) mo"
    }

    private var brandName: String {
        record.supportInfo?.providerName ?? record.merchantName ?? "the manufacturer"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                checklist

                // v3 animPassV3 §9 #6: the packet summary slides off the
                // right edge (a document changing hands) and a mono
                // SOLD · PASSED ON stamp takes its place — reusing
                // `PTStamp` + `stampEase` at a lower amplitude than the
                // paywall's MEMBER ✓ slam, per Ideas.html.
                Group {
                    if animPassOn && showHandoverStamp {
                        handoverStampRow
                    } else {
                        packetSummaryRow
                    }
                }
                .transition(handoverTransition)
                .animation(
                    animPassOn
                        ? AnimPass.animation(PTMotion.stampEase(AnimPass.Duration.handover), reduceMotion: reduceMotion)
                        : nil,
                    value: showHandoverStamp
                )

                Button {
                    Task { await handOver() }
                } label: {
                    HStack(spacing: 8) {
                        if isGenerating { ProgressView().tint(PT.inkStamp) }
                        Text(isGenerating ? "Preparing…" : "Hand it over")
                    }
                }
                .buttonStyle(PTGoldButtonStyle())
                .disabled(isGenerating || pageCount == 0)

                Text("Sharing doesn't remove the item — mark it \u{201C}passed on\u{201D} after the sale.")
                    .font(.system(size: 11))
                    .foregroundStyle(PT.txt3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                if hasShared {
                    markPassedOnRow
                }
            }
            .padding(.horizontal, PT.Metric.screenPad)
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
        .task {
            manualRecord = ManualStore.manual(for: record.id)
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                // item 10: `hasShared` (which arms "Mark as passed on")
                // flips on the share sheet's own completion, not on merely
                // presenting it — presenting isn't sharing.
                ShareSheetView(activityItems: [shareURL], onComplete: { hasShared = true })
            }
        }
        .ptToast($toast)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            (
                Text("A dossier for the ")
                    .foregroundStyle(PT.txt)
                + Text("next owner.")
                    .foregroundStyle(PT.gold)
                    .italic()
            )
            .font(PTFont.serif(28, weight: 600))

            Text("Listings with proof sell for more. Pick what the buyer sees — your price stays private unless you say so.")
                .font(.system(size: 12.5))
                .foregroundStyle(PT.txt3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: Checklist

    private var checklist: some View {
        VStack(spacing: 0) {
            // Fixed copy, not conditional on `showPricePaid` (item 2, HIGH):
            // (a) "serial", not "receipt image" — the generated PDF only
            // ever draws store/date/serial as text (`PassItOnPacketPDF`),
            // it never embeds the receipt image itself, so claiming
            // "receipt image" overclaimed what the buyer actually gets; and
            // (b) price redaction state is already the separate "Show price
            // paid" row below — this row's own copy stays fixed so it never
            // implies the price ships by default (it's off by default).
            checklistRow(
                title: "Proof of purchase",
                subtitle: hasProofOfPurchase ? "Store, date, serial · price REDACTED" : "No proof attached yet",
                isOn: hasProofOfPurchase ? $selection.includeProofOfPurchase : .constant(false)
            )
            .disabled(!hasProofOfPurchase)

            if hasRemainingWarranty {
                Rectangle().fill(PT.hair).frame(height: 1)
                checklistRow(
                    title: "Remaining warranty",
                    subtitle: "\(brandName) · \(monthsRemainingText) · transferability note included",
                    isOn: $selection.includeRemainingWarranty
                )
            }

            if hasServiceHistory {
                Rectangle().fill(PT.hair).frame(height: 1)
                checklistRow(
                    title: "Service history",
                    subtitle: serviceHistorySubtitle,
                    isOn: $selection.includeServiceHistory
                )
            }

            if let manualRecord {
                Rectangle().fill(PT.hair).frame(height: 1)
                checklistRow(
                    title: "Manual",
                    subtitle: "\(manualRecord.displayName) · adds \(manualRecord.formattedSize) · on this device only",
                    isOn: $selection.includeManual
                )
            }

            Rectangle().fill(PT.hair).frame(height: 1)
            checklistRow(
                title: "Show price paid",
                subtitle: selection.showPricePaid
                    ? "On — buyer sees the price you paid"
                    : "Off — buyer sees \u{201C}purchased \(purchasedMonthYearText)\u{201D} only",
                isOn: $selection.showPricePaid
            )
        }
        .padding(.vertical, 4)
        .background(Color(hex: 0xE7DCC4, alpha: 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PT.hair, lineWidth: 1))
    }

    private var serviceHistorySubtitle: String {
        let count = record.serviceEntries.count
        let noun = count == 1 ? "entry" : "entries"
        if let latest = record.serviceEntries.sortedByDateDescending.first {
            return "\(count) \(noun) · \(latest.title)"
        }
        return "\(count) \(noun)"
    }

    private var purchasedMonthYearText: String {
        guard let date = record.purchaseDate else { return "an earlier date" }
        return PTDate.monthYear.string(from: date)
    }

    private func checklistRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PTFont.serif(14.5, weight: 600))
                    .foregroundStyle(PT.txt)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(PT.txt3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(PT.sage)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Packet summary + mark-passed-on

    private var packetSummaryRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 15))
                .foregroundStyle(PT.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Buyer packet · \(pageCount) page\(pageCount == 1 ? "" : "s")")
                    .font(PTFont.serif(14, weight: 600))
                    .foregroundStyle(PT.txt)
                Text("PDF · footer \u{201C}Kept with PaperTrail\u{201D}")
                    .font(.system(size: 11))
                    .foregroundStyle(PT.txt3)
            }
            Spacer(minLength: 8)
            Text(estimatedSizeText)
                .font(PTFont.mono(11, medium: true))
                .foregroundStyle(PT.txt2)
        }
        .padding(14)
        .background(PT.inkCardDark, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// v3 animPassV3 §9 #6: what replaces `packetSummaryRow` once the
    /// handover is confirmed.
    private var handoverStampRow: some View {
        HStack {
            Spacer(minLength: 0)
            PTStamp(text: "SOLD · PASSED ON", state: .paper)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(PT.inkCardDark, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var handoverTransition: AnyTransition {
        guard animPassOn else { return .identity }
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.6).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    private var markPassedOnRow: some View {
        Button {
            record.passedOnDate = .now
            record.updatedAt = .now
            toast = PTToastItem(message: "Marked as passed on")
            if animPassOn { showHandoverStamp = true }
        } label: {
            Text(record.passedOnDate == nil ? "Mark as passed on" : "Marked as passed on \u{2713}")
        }
        .buttonStyle(PTOutlineButtonStyle())
        .disabled(record.passedOnDate != nil)
    }

    // MARK: Actions

    @MainActor
    private func handOver() async {
        isGenerating = true
        defer { isGenerating = false }

        let input = PassItOnPacketPDF.Input(
            productName: record.productName,
            merchantName: record.merchantName,
            purchaseDate: record.purchaseDate,
            amount: record.amount,
            currency: record.currency,
            serialNumber: record.serialNumber,
            warrantyExpiryDate: record.warrantyExpiryDate,
            coverageSummary: record.coverageSummary,
            serviceEntries: record.serviceEntries,
            manualURL: selection.includeManual ? ManualStore.url(for: record.id) : nil,
            selection: selection
        )

        // PDF rendering (full manual page embeds, text layout) runs off the
        // main actor in a detached task so it can't block the UI — same
        // pattern as `ExportView.buildInsuranceReportPDF`.
        let url = await Task.detached {
            PassItOnPacketPDF.generate(input)
        }.value

        guard let url else {
            toast = PTToastItem(message: "Couldn't build the packet")
            return
        }
        shareURL = url
        showShareSheet = true
        AppLogger.info("Pass-it-on packet shared for record \(record.id), \(pageCount) content page(s)", category: "passiton")
    }
}

#Preview {
    NavigationStack {
        Text("Preview requires SwiftData context")
    }
}
