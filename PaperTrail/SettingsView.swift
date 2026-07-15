import SwiftUI
import SwiftData
import UIKit
import CloudKit

/// Settings, rebuilt around outcomes (§1): a Library Card hero, then Reminders,
/// Your data, Household, Your library, Help & about, and iCloud & Your Data.
/// Every raw diagnostic now lives in `AdvancedDiagnosticsView` (§2) — nothing
/// technical greets a real person here, but nothing was deleted.
struct SettingsView: View {
    @Query private var records: [PurchaseRecord]
    @Query private var attachments: [Attachment]
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @AppStorage("activeSyncBackend") private var activeSyncBackend = "Unknown"
    @AppStorage("lastCloudSyncDate") private var lastCloudSyncRaw = 0.0
    @AppStorage(CommunityLearning.optOutKey) private var communityLearningEnabled = false
    @AppStorage("spotlightIndexingEnabled") private var spotlightIndexingEnabled = true

    private let reminders = ReminderSettings.shared

    @State private var showLoggedValueInfo = false
    @State private var iCloudStatusText = "Checking iCloud status…"
    @State private var iCloudStatusTone: Color = PT.txt3

    // MARK: Derived

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

    /// Records whose Proof Score is below "Claim-ready" (90) — how many still
    /// need a receipt, a serial number, or another proof field filled in.
    private var proofNeedingCount: Int {
        records.filter { record in
            let hasAttachment = attachments.contains { $0.recordID == record.id }
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

    private var householdSummary: String {
        let manager = HouseholdManager.shared
        let members = manager.members
        if members.isEmpty { return "Set up" }
        if !manager.isHouseholdOwner { return "Joined" }
        if members.contains(where: { $0.role == .invited }) { return "Invite sent" }
        return "\(members.count) member\(members.count == 1 ? "" : "s")"
    }

    private var storageSize: String {
        let totalBytes = attachments.reduce(into: 0) { total, attachment in
            let url = ImageStorageManager.url(for: attachment.localFilename)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            total += size
        }
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    private var lastSyncDate: Date? {
        lastCloudSyncRaw > 0 ? Date(timeIntervalSince1970: lastCloudSyncRaw) : nil
    }

    private var backupState: BackupState {
        currentBackupState(syncManager: cloudImageSync, activeSyncBackend: activeSyncBackend, lastSync: lastSyncDate)
    }

    var body: some View {
        @Bindable var reminders = reminders

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(PTFont.serif(34, weight: 600))
                    .foregroundStyle(PT.txt)
                    .padding(.bottom, 18)

                libraryCard
                    .padding(.bottom, 26)

                // Reminders
                SettingsSectionLabel(text: "Reminders")
                SettingsCard {
                    SettingsRow(
                        icon: "bell", iconColor: PT.gold, title: "Warranty reminders",
                        subtitle: reminders.warrantyRemindersEnabled ? "Before each warranty runs out" : "Off — you won't be warned",
                        toggle: $reminders.warrantyRemindersEnabled
                    )
                    if reminders.warrantyRemindersEnabled {
                        SettingsRowDivider()
                        Menu {
                            ForEach(WarrantyLeadTime.allCases) { lead in
                                Button(lead.label) { reminders.warrantyLeadTime = lead }
                            }
                        } label: {
                            SettingsRow(icon: "calendar", title: "Remind me", value: reminders.warrantyLeadTime.label, showChevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                    SettingsRowDivider()
                    SettingsRow(
                        icon: "arrow.uturn.backward", iconColor: PT.gold, title: "Return windows",
                        subtitle: "Warn before a return or refund period closes",
                        toggle: $reminders.returnWindowRemindersEnabled
                    )
                    SettingsRowDivider()
                    SettingsRow(
                        icon: "calendar.badge.clock", iconColor: PT.gold, title: "Monthly coverage digest",
                        subtitle: "One summary of what's expiring and closing",
                        toggle: $reminders.digestEnabled
                    )
                    SettingsRowDivider()
                    SettingsRow(
                        icon: "sparkles", iconColor: PT.gold, title: "Suggest support contacts",
                        subtitle: "Look up brand help lines when something breaks",
                        toggle: $reminders.suggestSupportContacts
                    )
                }
                .padding(.bottom, 22)

                // Your data
                SettingsSectionLabel(text: "Your data")
                SettingsCard {
                    NavigationLink { ExportView() } label: {
                        SettingsRow(icon: "square.and.arrow.up", iconColor: PT.gold, title: "Export everything",
                                    subtitle: "A full copy — PDF + CSV, no lock-in", showChevron: true)
                    }.buttonStyle(.plain)
                    SettingsRowDivider()
                    NavigationLink { ImportView() } label: {
                        SettingsRow(icon: "tray.and.arrow.down", iconColor: PT.gold, title: "Import receipts",
                                    subtitle: "From Photos, Files, or your inbox", showChevron: true)
                    }.buttonStyle(.plain)
                    SettingsRowDivider()
                    SettingsRow(icon: "brain", iconColor: PT.gold, title: "Share anonymous learning data",
                                subtitle: "Merchant patterns only — never your purchases",
                                toggle: $communityLearningEnabled)
                    SettingsRowDivider()
                    SettingsRow(icon: "magnifyingglass", iconColor: PT.gold, title: "Show records in iOS search",
                                subtitle: "Find receipts from the Home Screen",
                                toggle: $spotlightIndexingEnabled)
                    SettingsRowDivider()
                    SettingsRow(icon: "lock", iconColor: PT.sage, title: "Records are private",
                                subtitle: "Stored in your iCloud — only you can see them")
                }
                .padding(.bottom, 22)

                // Household
                SettingsSectionLabel(text: "Household")
                SettingsCard {
                    NavigationLink { HouseholdView() } label: {
                        SettingsRow(icon: "person.2", iconColor: PT.gold, title: "Family sharing",
                                    subtitle: "Share proof with the people you live with",
                                    value: householdSummary, showChevron: true)
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 22)

                // Your library
                SettingsSectionLabel(text: "Your library")
                SettingsCard {
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
                    NavigationLink { ProofFixListView() } label: {
                        SettingsRow(icon: "checkmark.seal", title: "Proof completeness",
                                    value: proofNeedingCount > 0 ? "\(proofNeedingCount) need proof" : "All claim-ready",
                                    showChevron: true)
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 22)

                // Help & about
                SettingsSectionLabel(text: "Help & about")
                SettingsCard {
                    SettingsRow(icon: "questionmark.circle", title: "Help & support", showChevron: true,
                                action: { openURL("https://papertrail.kaopeh.com") })
                    SettingsRowDivider()
                    SettingsRow(icon: "hand.raised", title: "Privacy policy", showChevron: true,
                                action: { openURL("https://papertrail.kaopeh.com/privacy") })
                    SettingsRowDivider()
                    SettingsRow(icon: "star", title: "Rate PaperTrail", showChevron: true,
                                action: { openURL("https://apps.apple.com/app/id6788663812?action=write-review") })
                    SettingsRowDivider()
                    NavigationLink { AdvancedDiagnosticsView() } label: {
                        SettingsRow(icon: "gearshape.2", title: "Advanced & Diagnostics",
                                    subtitle: "Sync details & support info", showChevron: true)
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 22)

                // iCloud & Your Data
                SettingsSectionLabel(text: "iCloud & Your Data")
                SettingsCard {
                    SettingsRow(icon: "icloud", iconColor: iCloudStatusTone, title: iCloudStatusText)
                }
                .padding(.bottom, 10)
                Text("Your records and images are stored on this device and in your private iCloud. Nobody else — including the developer — can access them.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(PT.txt3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 18)

                // Footer
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
            .padding(.top, 4)
            .padding(.bottom, 120)
        }
        .ptScreen()
        .toolbar(.hidden, for: .navigationBar)
        .task { await refreshICloudStatus() }
        .task { await HouseholdManager.shared.refresh() }
        .alert("Logged value", isPresented: $showLoggedValueInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(itemCount) item\(itemCount == 1 ? "" : "s") · \(totalValue) logged. Handy for insurance & claims.")
        }
    }

    // MARK: - Library Card hero

    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PAPERTRAIL · LIBRARY CARD")
                    .ptMonoLabel(9.5, tracking: 2.4)
                    .foregroundStyle(PT.goldDeep)
                Spacer()
                Text("EST. 2026")
                    .font(PTFont.mono(9.5))
                    .tracking(1.4)
                    .foregroundStyle(PT.onPaper3)
            }
            .padding(.bottom, 14)

            HStack(spacing: 12) {
                PTAvatar(size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your library")
                        .font(PTFont.serif(20, weight: 600))
                        .foregroundStyle(PT.onPaper)
                    Text("Synced privately via iCloud")
                        .font(.system(size: 12.5))
                        .foregroundStyle(PT.onPaper2)
                }
                Spacer()
            }

            GoldRule()
                .padding(.vertical, 14)

            HStack {
                BackupStatusBadge(state: backupState, onRetry: retryBackup)
                Spacer()
                Text("\(itemCount) ITEMS · \(totalValue)")
                    .font(PTFont.mono(10))
                    .tracking(0.6)
                    .foregroundStyle(PT.onPaper3)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 15, trailing: 18))
        .frame(maxWidth: .infinity)
        .paperCard(goldFold: true)
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Actions

    private func refreshICloudStatus() async {
        let container = CKContainer(identifier: "iCloud.nikhilsh.PaperTrail")
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            iCloudStatusText = "iCloud account not signed in — data stays on this device"
            iCloudStatusTone = PT.txt3
            return
        }
        switch status {
        case .available:
            iCloudStatusText = "Syncing with iCloud"
            iCloudStatusTone = PT.sage
        case .restricted:
            iCloudStatusText = "iCloud restricted"
            iCloudStatusTone = PT.amber
        case .noAccount, .couldNotDetermine, .temporarilyUnavailable:
            iCloudStatusText = "iCloud account not signed in — data stays on this device"
            iCloudStatusTone = PT.txt3
        @unknown default:
            iCloudStatusText = "iCloud account not signed in — data stays on this device"
            iCloudStatusTone = PT.txt3
        }
    }

    private func retryBackup() {
        Task {
            let infos = attachments.map { AttachmentSyncInfo(id: $0.id, localFilename: $0.localFilename) }
            await cloudImageSync.uploadMissingImages(attachments: infos)
            await cloudImageSync.syncMissingImages(attachments: infos)
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
    .environmentObject(CloudImageSyncManager.shared)
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
