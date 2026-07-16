import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// "Your data, yours." (§3) — the #1 trust feature. Builds a real CSV + per-record
/// PDFs + a combined proof book for **all** records, offered via the share sheet
/// or Save-to-Files.
struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [PurchaseRecord]
    @Query private var attachments: [Attachment]

    @State private var isBuilding = false
    @State private var bundleURL: URL?
    @State private var showShareSheet = false
    @State private var showFileExporter = false
    @State private var errorMessage: String?

    @State private var isBuildingReport = false
    @State private var reportURL: URL?
    @State private var showReportShareSheet = false
    /// PaperTrail Plus gate for the Home Inventory Report — offers a
    /// single-room free preview instead of generating straight away.
    @State private var showReportGateDialog = false
    @State private var showPaywall = false

    private var recordCount: Int { records.count }
    private var documentCount: Int { attachments.count }

    /// Whole-home report requires Plus (docs/MONETIZATION.md — free tier is
    /// one room). `false` whenever the flag is off, so the badge/dialog never
    /// appear and "Generate report" behaves exactly as it does today.
    private var reportNeedsPlus: Bool {
        PlusConfig.enabled && !PlusEntitlements.shared.hasPlus
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(Text("Your data,\n").foregroundStyle(PT.txt))\(Text("yours.").foregroundStyle(PT.goldHi))")
                        .font(PTFont.serif(34, weight: 600))
                    Text("Take a full copy with you anytime — no lock-in. If you ever leave PaperTrail, you leave with everything.")
                        .font(.system(size: 14))
                        .foregroundStyle(PT.txt2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                manifestCard

                VStack(spacing: 10) {
                    Button { Task { await buildAndShare() } } label: {
                        HStack(spacing: 8) {
                            if isBuilding { ProgressView().tint(PT.inkStamp) }
                            Text(isBuilding ? "Preparing…" : "Export \(recordCount) record\(recordCount == 1 ? "" : "s")")
                        }
                    }
                    .buttonStyle(PTGoldButtonStyle())
                    .disabled(isBuilding || records.isEmpty)

                    Button { Task { await buildForFiles() } } label: {
                        Label("Save a copy to Files", systemImage: "folder")
                    }
                    .buttonStyle(PTOutlineButtonStyle())
                    .disabled(isBuilding || records.isEmpty)
                }

                insuranceReportCard

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock")
                        .font(.system(size: 11))
                        .foregroundStyle(PT.sage)
                    Text("Your records live in your own iCloud. PaperTrail's servers never see them — and this export proves it: it's the complete, readable copy.")
                        .font(.system(size: 12))
                        .foregroundStyle(PT.txt3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.bottom, 130)
        }
        .ptScreen()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Settings")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let bundleURL { ShareSheetView(activityItems: [bundleURL]) }
        }
        .sheet(isPresented: $showFileExporter) {
            if let bundleURL { DocumentExporter(url: bundleURL) }
        }
        .sheet(isPresented: $showReportShareSheet) {
            if let reportURL { ShareSheetView(activityItems: [reportURL]) }
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
                .tint(PT.gold)
                .preferredColorScheme(.dark)
        }
        .confirmationDialog("Home Inventory Report", isPresented: $showReportGateDialog, titleVisibility: .visible) {
            Button("Preview one room") { Task { await buildAndShareReport(restrictToHighestValueRoom: true) } }
            Button("Get Plus") { showPaywall = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Free preview covers your highest-value room. The full whole-home report is part of PaperTrail Plus.")
        }
        .alert("Export failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var manifestCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("IN YOUR EXPORT")
                .ptMonoLabel(9.5, tracking: 2.4)
                .foregroundStyle(PT.onPaper3)
                .padding(.bottom, 14)

            manifestRow(icon: "doc.text", title: "\(recordCount) record\(recordCount == 1 ? "" : "s")",
                        sub: "Every item, organized")
            manifestDivider
            manifestRow(icon: "square.stack.3d.up", title: "\(documentCount) document\(documentCount == 1 ? "" : "s") · PDF",
                        sub: "Receipts & warranty cards, full quality")
            manifestDivider
            manifestRow(icon: "list.bullet", title: "Details · CSV",
                        sub: "Prices, dates, serials, warranties")
            manifestDivider
            manifestRow(icon: "checkmark.shield", title: "A printable proof book",
                        sub: "One PDF you can hand to anyone")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: false)
    }

    private func manifestRow(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(PT.goldDeep)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PTFont.serif(16, weight: 600))
                    .foregroundStyle(PT.onPaper)
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(PT.onPaper2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }

    private var manifestDivider: some View {
        Rectangle().fill(PT.onPaperHair).frame(height: 1)
    }

    /// The insurance-ready home inventory PDF — every local item, grouped by
    /// room, with estimated current value. The app's anti-lock-in showcase:
    /// the artifact a user hands their insurer after a burglary/fire/flood.
    private var insuranceReportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                Image(systemName: "house.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(PT.goldDeep)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Home Inventory Report")
                            .font(PTFont.serif(16, weight: 600))
                            .foregroundStyle(PT.onPaper)
                        if reportNeedsPlus {
                            Text("PLUS")
                                .font(PTFont.mono(8.5, medium: true))
                                .tracking(1.0)
                                .foregroundStyle(PT.inkStamp)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PT.goldFoil, in: Capsule())
                        }
                    }
                    Text("Everything you own, by room — ready for your insurer")
                        .font(.system(size: 12))
                        .foregroundStyle(PT.onPaper2)
                }
                Spacer(minLength: 0)
            }

            Button {
                if reportNeedsPlus {
                    showReportGateDialog = true
                } else {
                    Task { await buildAndShareReport() }
                }
            } label: {
                HStack(spacing: 8) {
                    if isBuildingReport { ProgressView().tint(PT.inkStamp) }
                    Text(isBuildingReport ? "Preparing…" : "Generate report")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PTOutlineButtonStyle())
            .disabled(isBuildingReport || records.isEmpty)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: false)
    }

    // MARK: Actions

    @MainActor
    private func buildBundle() async -> URL? {
        isBuilding = true
        defer { isBuilding = false }
        // Snapshot the queried models on the main actor, then build off the URL.
        let recs = records
        let atts = attachments
        do {
            return try await ExportService.buildBundle(records: recs, allAttachments: atts)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func buildAndShare() async {
        guard let url = await buildBundle() else { return }
        bundleURL = url
        showShareSheet = true
    }

    private func buildForFiles() async {
        guard let url = await buildBundle() else { return }
        bundleURL = url
        showFileExporter = true
    }

    /// Builds the Home Inventory Report PDF. `records`/`attachments` come
    /// straight from `@Query`, so the snapshot into `InsuranceReport.Report`
    /// (pure value types — no SwiftData model references, see
    /// `InsuranceReport.Item`) happens on the main actor; the actual PDF
    /// rendering — full-res image decodes and PDF drawing — then runs off
    /// the main actor in a detached task so it can't block the UI.
    @MainActor
    private func buildInsuranceReportPDF(restrictToHighestValueRoom: Bool = false) async -> URL? {
        isBuildingReport = true
        let report = InsuranceReport.build(records: records, attachments: attachments,
                                            restrictToHighestValueRoom: restrictToHighestValueRoom)
        let url = await Task.detached {
            InsuranceReportPDF.generate(report)
        }.value
        isBuildingReport = false
        guard let url else {
            errorMessage = "Couldn't build the report."
            return nil
        }
        return url
    }

    private func buildAndShareReport(restrictToHighestValueRoom: Bool = false) async {
        guard let url = await buildInsuranceReportPDF(restrictToHighestValueRoom: restrictToHighestValueRoom) else { return }
        reportURL = url
        showReportShareSheet = true
    }
}

/// Presents the system "Save to Files" UI for an on-disk file.
struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
