import SwiftUI
import SwiftData

/// "Help & about" (v2 Settings front desk, S1 §5) — the drill-in one level
/// below Settings' top-level "Help & about" row. Carries every row that
/// doesn't answer a single outcome on its own: help, policy, rating, the
/// "Your library" stat rows (proof completeness, logged value, categories,
/// storage), Advanced & Diagnostics, the PaperTrail Plus status/restore
/// rows, and the version footer. Nothing here is new — everything moved
/// verbatim from the old top-level Settings surface.
struct HelpAboutSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [PurchaseRecord]
    @Query private var attachments: [Attachment]

    @State private var showLoggedValueInfo = false
    @State private var showPaywall = false

    // MARK: Derived — same computations as the old Settings "Your library" card.

    private var itemCount: Int { records.count }

    private var totalValue: String {
        let sum = records.compactMap(\.amount).reduce(0, +)
        let currency = records.compactMap(\.currency).first ?? "SGD"
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: sum)) ?? "—"
    }

    private var roomCount: Int { Set(records.compactMap(\.room).filter { !$0.isEmpty }).count }

    /// Records whose Proof Score is below "Proof complete" (90) — how many
    /// still need a document, a serial number, or another proof field filled
    /// in. Groups attachments by `recordID` once so the count is O(records +
    /// attachments) rather than scanning every attachment per record.
    private var proofNeedingCount: Int {
        let attachmentsByRecord = Dictionary(grouping: attachments, by: \.recordID)
        return records.filter { record in
            let hasAttachment = attachmentsByRecord[record.id] != nil
            let snapshot = ProofScoreSnapshot(
                hasAttachment: hasAttachment,
                purchaseDate: record.purchaseDate,
                amount: record.amount,
                warrantyExpiryDate: record.warrantyExpiryDate,
                serialNumber: record.serialNumber,
                productImageAttachmentID: record.productImageAttachmentID
            )
            return ProofScore(snapshot: snapshot).score < 90
        }.count
    }

    private var storageSize: String {
        let totalBytes = attachments.reduce(into: 0) { total, attachment in
            let url = ImageStorageManager.url(for: attachment.localFilename)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            total += size
        }
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(Text("Help &\n").foregroundStyle(PT.txt))\(Text("about.").foregroundStyle(PT.goldHi))")
                        .font(PTFont.serif(30, weight: 600))
                    Text("Guides, policy, and everything about how PaperTrail keeps your proof.")
                        .font(.system(size: 14))
                        .foregroundStyle(PT.txt2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                SettingsCard {
                    SettingsRow(icon: "questionmark.circle", title: "Help & support", showChevron: true,
                                action: { openURL("https://papertrail.kaopeh.com") })
                    SettingsRowDivider()
                    SettingsRow(icon: "hand.raised", title: "Privacy policy", showChevron: true,
                                action: { openURL("https://papertrail.kaopeh.com/privacy") })
                    SettingsRowDivider()
                    SettingsRow(icon: "star", title: "Rate PaperTrail", showChevron: true,
                                action: { openURL("https://apps.apple.com/app/id6788663812?action=write-review") })
                }

                SettingsSectionLabel(text: "Your library")
                SettingsCard {
                    NavigationLink { ProofFixListView() } label: {
                        SettingsRow(icon: "checkmark.seal", title: "Proof completeness",
                                    value: proofNeedingCount > 0 ? "\(proofNeedingCount) need proof" : "All proof complete",
                                    showChevron: true)
                    }.buttonStyle(.plain)
                    SettingsRowDivider()
                    SettingsRow(icon: "square.stack.3d.up", title: "Logged value",
                                subtitle: "Handy for insurance & claims",
                                value: totalValue, showChevron: true,
                                action: { showLoggedValueInfo = true })
                    SettingsRowDivider()
                    SettingsRow(icon: "square.grid.2x2", title: "Categories", subtitle: "Rooms & types",
                                value: "\(roomCount) room\(roomCount == 1 ? "" : "s")")
                    SettingsRowDivider()
                    SettingsRow(icon: "shippingbox", title: "Storage",
                                value: storageSize)
                    SettingsRowDivider()
                    NavigationLink { AdvancedDiagnosticsView() } label: {
                        SettingsRow(icon: "gearshape.2", title: "Advanced & Diagnostics",
                                    subtitle: "Sync details & support info", showChevron: true)
                    }.buttonStyle(.plain)
                }

                if PlusConfig.enabled {
                    SettingsSectionLabel(text: "PaperTrail Plus")
                    SettingsCard {
                        SettingsRow(icon: "sparkles", iconColor: PT.gold, title: "PaperTrail Plus",
                                    value: PlusEntitlements.shared.hasPlus ? "Plus" : "Free", showChevron: true,
                                    action: { showPaywall = true })
                        SettingsRowDivider()
                        SettingsRow(icon: "arrow.clockwise", iconColor: PT.gold, title: "Restore purchases",
                                    action: { Task { await PlusEntitlements.shared.restore() } })
                    }
                }

                VStack(spacing: 4) {
                    Text("PaperTrail · Version \(versionString)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(PT.txt3)
                    Text("Proof of purchase, ready the day you need it.")
                        .font(PTFont.serif(13, weight: 500, italic: true))
                        .foregroundStyle(PT.txt3)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
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
                        Text("Settings")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
                .tint(PT.gold)
                .preferredColorScheme(.dark)
        }
        .alert("Logged value", isPresented: $showLoggedValueInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(itemCount) item\(itemCount == 1 ? "" : "s") · \(totalValue) logged. Handy for insurance & claims.")
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        HelpAboutSettingsView()
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
