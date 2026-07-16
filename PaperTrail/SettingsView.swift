import SwiftUI
import SwiftData
import UIKit
import StoreKit

/// Settings, rebuilt as the v2 "front desk" (docs/design-v2/V2_BRIEF.md §1,
/// S1): a Library Card hero (re-struck in gold once Plus is active — P3) and
/// exactly four rows — Reminders, Household, Your data, Help & about — each
/// a one-tap drill-in to a screen that carries everything that used to live
/// directly on this surface. Nothing was deleted; every old row is still
/// here, one level down. The standalone "iCloud & Your Data" status card is
/// gone too, but not the information it carried: the library card's own
/// SYNC row now tells the same honest truth (reusing `backupState`, the
/// signal that already drove this card's badge), and the raw CloudKit
/// account status still lives in Advanced & Diagnostics ("iCloud account"),
/// unchanged.
struct SettingsView: View {
    @Query private var records: [PurchaseRecord]
    @Query private var attachments: [Attachment]
    @EnvironmentObject private var cloudImageSync: CloudImageSyncManager
    @AppStorage("activeSyncBackend") private var activeSyncBackend = "Unknown"
    @AppStorage("lastCloudSyncDate") private var lastCloudSyncRaw = 0.0

    private let reminders = ReminderSettings.shared

    /// PaperTrail Plus paywall — presented from the Plus band on the library
    /// card (tapping the gold member card's MANAGE › goes to the App Store
    /// instead, via `manageSubscriptions()`).
    @State private var showPaywall = false
    /// Yearly product's live `displayPrice`, loaded once StoreKit answers.
    /// `nil` until then — the band shows the static "S$29.98" house copy in
    /// the meantime, never a blank price.
    @State private var yearlyPriceText: String?
    /// Member-card params sourced from the live entitlement transaction —
    /// basic wiring only; trial/lapse presentation refinements are Wave D's
    /// job (see `Design/V2/GoldMemberCard.swift`).
    @State private var membershipInfo: PlusMembershipInfo?

    private struct PlusMembershipInfo {
        let memberNumber: String
        let term: PTMembershipTerm
    }

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

    private var householdSummary: String {
        let manager = HouseholdManager.shared
        let members = manager.members
        if members.isEmpty { return "Set up" }
        if !manager.isHouseholdOwner { return "Joined" }
        if members.contains(where: { $0.role == .invited }) { return "Invite sent" }
        return "\(members.count) member\(members.count == 1 ? "" : "s")"
    }

    private var lastSyncDate: Date? {
        lastCloudSyncRaw > 0 ? Date(timeIntervalSince1970: lastCloudSyncRaw) : nil
    }

    private var backupState: BackupState {
        currentBackupState(syncManager: cloudImageSync, activeSyncBackend: activeSyncBackend, lastSync: lastSyncDate)
    }

    /// The mono row's left-hand label — "SYNCED · N ITEMS · $X,XXX" honest
    /// states (§1): never a fake green, always the real backup state.
    private var syncCapsLabel: String {
        switch backupState {
        case .synced: "SYNCED"
        case .syncing: "SYNCING"
        case .paused: "SYNC PAUSED"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(PTFont.serif(34, weight: 600))
                    .foregroundStyle(PT.txt)
                    .padding(.bottom, 18)

                heroCard
                    .padding(.bottom, 26)

                SettingsCard {
                    NavigationLink { RemindersSettingsView() } label: {
                        SettingsRow(icon: "bell", iconColor: PT.gold, title: "Reminders",
                                    subtitle: "Warranty · returns · monthly digest",
                                    value: reminders.warrantyRemindersEnabled ? "On" : "Off",
                                    showChevron: true)
                    }.buttonStyle(.plain)
                    SettingsRowDivider()
                    NavigationLink { HouseholdView() } label: {
                        SettingsRow(icon: "person.2", iconColor: PT.gold, title: "Household",
                                    subtitle: "Share proof with people you live with",
                                    value: householdSummary, showChevron: true)
                    }.buttonStyle(.plain)
                    SettingsRowDivider()
                    NavigationLink { YourDataSettingsView() } label: {
                        SettingsRow(icon: "folder", iconColor: PT.gold, title: "Your data",
                                    subtitle: "Export, import, privacy — no lock-in", showChevron: true)
                    }.buttonStyle(.plain)
                    SettingsRowDivider()
                    NavigationLink { HelpAboutSettingsView() } label: {
                        SettingsRow(icon: "questionmark.circle", iconColor: PT.gold, title: "Help & about",
                                    subtitle: "Guides, policy, diagnostics", showChevron: true)
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 18)

                Text("Your records and images are stored on this device and in your private iCloud. Nobody else — including the developer — can access them.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(PT.txt3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.top, 4)
            .padding(.bottom, 120)
        }
        .ptScreen()
        .toolbar(.hidden, for: .navigationBar)
        .task { await HouseholdManager.shared.refresh() }
        .task { await loadYearlyPrice() }
        .task { await loadMembershipInfo() }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
                .tint(PT.gold)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Hero: library card (free) / gold member card (Plus, P3)

    @ViewBuilder
    private var heroCard: some View {
        if PlusConfig.enabled, PlusEntitlements.shared.hasPlus, let membershipInfo {
            GoldMemberCard(
                name: "Your library",
                memberNumber: membershipInfo.memberNumber,
                term: membershipInfo.term,
                itemCount: itemCount,
                totalValue: totalValue,
                synced: !backupState.isPaused,
                onManage: manageSubscriptions
            )
        } else {
            libraryCard
        }
    }

    private var libraryCard: some View {
        PaperCardV2(goldFold: true) {
            VStack(alignment: .leading, spacing: 0) {
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
                            // Backup recency line — honest state, never static copy.
                            Text(backupState.text)
                                .font(.system(size: 12.5))
                                .foregroundStyle(PT.onPaper2)
                        }
                        Spacer()
                    }

                    GoldRule()
                        .padding(.vertical, 14)

                    syncRow
                }
                .padding(EdgeInsets(top: 16, leading: 18, bottom: 15, trailing: 18))

                PlusBand(
                    tagline: "Annual membership · first 2 weeks free",
                    priceText: "\(yearlyPriceText ?? "S$29.98")/YR",
                    action: { showPaywall = true }
                )
            }
        }
    }

    private var syncRow: some View {
        Group {
            if backupState.isPaused {
                Button(action: retryBackup) { syncRowContent }.buttonStyle(.plain)
            } else {
                syncRowContent
            }
        }
    }

    private var syncRowContent: some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(backupState.dotColor).frame(width: 6, height: 6)
                Text(syncCapsLabel)
            }
            .font(PTFont.mono(11, medium: true))
            .tracking(1.1)
            .foregroundStyle(backupState.dotColor)
            Spacer()
            Text("\(itemCount) ITEM\(itemCount == 1 ? "" : "S") · \(totalValue)")
                .font(PTFont.mono(11))
                .tracking(1.1)
                .foregroundStyle(PT.onPaper2)
        }
    }

    // MARK: - Actions

    private func retryBackup() {
        Task {
            let infos = attachments.map { AttachmentSyncInfo(id: $0.id, localFilename: $0.localFilename) }
            await cloudImageSync.uploadMissingImages(attachments: infos)
            await cloudImageSync.syncMissingImages(attachments: infos)
        }
    }

    /// Live StoreKit price for the yearly product — falls back to the
    /// spec's static house copy ("S$29.98") until (or unless) it loads.
    private func loadYearlyPrice() async {
        guard PlusConfig.enabled else { return }
        guard let product = try? await Product.products(for: [PlusConfig.ProductID.yearly]).first else { return }
        yearlyPriceText = product.displayPrice
    }

    /// Basic wiring (P3): reads the live Plus entitlement transaction for
    /// the gold member card's member № and term. Trial/lapse presentation
    /// refinements are Wave D's job — this just gets honest values on screen.
    private func loadMembershipInfo() async {
        guard PlusConfig.enabled, PlusEntitlements.shared.hasPlus else {
            membershipInfo = nil
            return
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  PlusConfig.ProductID.all.contains(transaction.productID) else { continue }

            let number = memberNumber(fromTransactionID: String(transaction.originalID))
            let renewalText = transaction.expirationDate.map { dateFormatter.string(from: $0) } ?? "—"
            let term: PTMembershipTerm
            if transaction.offerType == .introductory {
                term = .trial(billsOn: renewalText)
            } else if transaction.productID == PlusConfig.ProductID.monthly {
                term = .monthly(renewsOn: renewalText)
            } else {
                term = .annual(renewsOn: renewalText)
            }
            membershipInfo = PlusMembershipInfo(memberNumber: number, term: term)
            return
        }
        membershipInfo = nil
    }

    /// Wires the gold card's MANAGE › to the real App Store subscription
    /// management sheet (same call PlusDebugView uses for its own "Manage
    /// subscriptions" debug action).
    private func manageSubscriptions() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        Task {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
            } catch {
                AppLogger.error("Settings: manage subscriptions failed: \(error.localizedDescription)", category: "plus")
            }
        }
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
