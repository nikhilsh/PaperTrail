import SwiftUI
import SwiftData
import UIKit
import StoreKit
import UserNotifications

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// PaperTrail Plus paywall — presented from the Plus band / lapsed renew
    /// band on the library card (tapping the gold member card's MANAGE ›
    /// goes to the App Store instead, via `manageSubscriptions()`).
    @State private var showPaywall = false
    /// Snapshot of `hasPlus` taken the moment the paywall is opened, so
    /// `handlePaywallDismiss` can tell "just converted" apart from "already
    /// had Plus, dismissed without changing anything" — that's what gates
    /// the "struck in gold" toast (ANIMATION_SPEC §4).
    @State private var hadPlusWhenPaywallOpened = false
    @State private var toast: PTToastItem?
    /// Yearly product's live `displayPrice`, loaded once StoreKit answers.
    /// `nil` until then — the band shows the static "S$29.98" house copy in
    /// the meantime, never a blank price.
    @State private var yearlyPriceText: String?
    /// Member-card params sourced from the live entitlement transaction.
    @State private var membershipInfo: PlusMembershipInfo?

    private struct PlusMembershipInfo {
        let memberNumber: String
        let term: PTMembershipTerm
        /// Denied/undetermined system notification permission — passed
        /// through to `GoldMemberCard` so its footer can honestly disclose
        /// when it's promising a "knock" that won't actually fire (§3c).
        let notificationsAuthorized: Bool
    }

    // MARK: Derived

    /// Same passed-on exclusion every other aggregation surface applies
    /// (`LibraryView`, `WarrantyView`, `WidgetSnapshotWriter`,
    /// `DigestScheduler`) — item 8, MEDIUM: Settings' library-card counts
    /// were the one place still counting sold/given-away items.
    private var activeRecords: [PurchaseRecord] {
        records.filter { !PassItOnAggregation.isExcludedFromAggregates(passedOnDate: $0.passedOnDate, flagOn: FeatureFlags.isOn(.passItOn)) }
    }

    private var itemCount: Int { activeRecords.count }

    private var totalValue: String {
        let sum = activeRecords.compactMap(\.amount).reduce(0, +)
        let currency = activeRecords.compactMap(\.currency).first ?? "SGD"
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
        case .neverSynced: "NOT SYNCED"
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
        .onChange(of: PlusEntitlements.shared.hasPlus) {
            // Catches every path that can flip `hasPlus` besides this
            // screen's own paywall sheet — PlusDebugView's "Simulate Plus"/
            // direct buy, a background `Transaction.updates` event, etc. —
            // so the gold card shows up wherever the purchase actually
            // happened (§5), not only when it happened through this screen.
            Task { await loadMembershipInfo() }
        }
        .sheet(isPresented: $showPaywall, onDismiss: handlePaywallDismiss) {
            NavigationStack { PaywallView() }
                .tint(PT.gold)
                .preferredColorScheme(.dark)
        }
        .ptToast($toast)
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
                syncState: syncChipState(for: backupState),
                notificationsAuthorized: membershipInfo.notificationsAuthorized,
                onManage: manageAction(for: membershipInfo.term)
            )
        } else {
            libraryCard
        }
    }

    /// Lifetime has no App Store subscription to manage. Pulled out of the
    /// `heroCard` `@ViewBuilder` body as a plain function call, and written
    /// as `if`/`return` rather than a ternary — `nil : manageSubscriptions`
    /// (a bound method reference) was too much for the type checker to even
    /// produce a diagnostic for (CI: "failed to produce diagnostic for
    /// expression"), whether inline in the call, hoisted to a `let`, or
    /// returned from a ternary in this same function.
    private func manageAction(for term: PTMembershipTerm) -> (() -> Void)? {
        if term == .lifetime {
            return nil
        }
        return manageSubscriptions
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

                // Lapsed members (were Plus, aren't now) get the quiet renew
                // band instead of the ordinary upsell — v2.1 spec: "No red,
                // no drama, nothing deleted."
                if PlusEntitlements.shared.isLapsed {
                    LapsedRenewBand(
                        priceText: "\(yearlyPriceText ?? "S$29.98")/yr",
                        action: openPaywall
                    )
                } else {
                    PlusBand(
                        tagline: "Annual membership · first 2 weeks free",
                        priceText: "\(yearlyPriceText ?? "S$29.98")/YR",
                        action: openPaywall
                    )
                }
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
                // v3 animPassV3 §9 #8 "Odometer numbers": rolls to a new
                // value instead of snapping — never on mere appearance,
                // since `.animation(value:)` only fires on an actual change.
                // Reduce Motion: `.numericText()` rolls digits regardless of
                // the `.animation` curve driving it — RM needs the
                // transition itself swapped out, not just a faster curve
                // (item 10).
                .contentTransition(FeatureFlags.isOn(.animPassV3) && !reduceMotion ? .numericText() : .identity)
                .animation(
                    FeatureFlags.isOn(.animPassV3) ? PTMotion.reduced(.default, reduceMotion: reduceMotion) : nil,
                    value: "\(itemCount)-\(totalValue)"
                )
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

    /// Reads the live Plus entitlement transaction for the gold member
    /// card's member № and term (`PTMembershipTerm.from`, annual/monthly/
    /// trial/lifetime). When Plus just lapsed (was shown, now isn't), the
    /// card's own crossfade back to cream is driven by animating the switch
    /// here (ANIMATION_SPEC §9: 600ms, on next Settings visit) — a fresh
    /// grant doesn't need this wrapper because `GoldMemberCard` animates its
    /// own gold-strike entrance on appear.
    ///
    /// More than one entitlement can be simultaneously "current" (a legacy
    /// lifetime purchase alongside a live subscription) — `currentEntitlements`
    /// doesn't order them, so `PlusEntitlements.preferredMembership` picks
    /// the one that should actually drive the card (§5: active subscription
    /// over legacy lifetime, latest expiration among subscriptions).
    private func loadMembershipInfo() async {
        guard PlusConfig.enabled, PlusEntitlements.shared.hasPlus else {
            if membershipInfo != nil {
                withAnimation(PTMotion.reduced(.easeInOut(duration: 0.6), reduceMotion: reduceMotion)) {
                    membershipInfo = nil
                }
            }
            return
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"

        // Qualified `StoreKit.Transaction`: SwiftUI also exports a
        // `Transaction` type (animation transactions), which is ambiguous
        // for an explicit type annotation once a file imports both
        // (mirrors `PlusDebugView`'s same qualification).
        var candidates: [StoreKit.Transaction] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  PlusConfig.ProductID.all.contains(transaction.productID) else { continue }
            candidates.append(transaction)
        }

        guard let transaction = PlusEntitlements.preferredMembership(among: candidates, expirationDate: \.expirationDate) else {
            membershipInfo = nil
            return
        }

        let number = memberNumber(fromTransactionID: String(transaction.originalID))
        let renewalText = transaction.expirationDate.map { dateFormatter.string(from: $0) } ?? "—"
        let monthlyDayText = transaction.expirationDate.map { PTMembershipTerm.ordinalDayText(for: $0) } ?? ""
        let term = PTMembershipTerm.from(
            productID: transaction.productID,
            isIntroductoryOffer: transaction.offerType == .introductory,
            renewalDateText: renewalText,
            lifetimeProductID: PlusConfig.ProductID.lifetime,
            monthlyProductID: PlusConfig.ProductID.monthly,
            monthlyDayText: monthlyDayText
        )
        let notificationsAuthorized = await currentNotificationsAuthorized()
        membershipInfo = PlusMembershipInfo(memberNumber: number, term: term, notificationsAuthorized: notificationsAuthorized)
    }

    /// Maps the honest library-card backup state to the gold card's
    /// three-value sync chip (§6) — never reads "SYNCED" while a transfer
    /// is actually still in flight, and never fabricates a synced state at
    /// all before the first backup completes.
    private func syncChipState(for backupState: BackupState) -> PTSyncChipState {
        switch backupState {
        case .synced: .synced
        case .syncing: .syncing
        case .paused, .neverSynced: .paused
        }
    }

    /// Whether the system would actually deliver a local notification right
    /// now — `.authorized`/`.provisional`/`.ephemeral` only. Used to decide
    /// whether the gold card's renewal-knock promise needs the honest
    /// "turn on notifications" disclosure (§3c).
    private func currentNotificationsAuthorized() async -> Bool {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        case .denied, .notDetermined: false
        @unknown default: false
        }
    }

    /// Snapshots `hasPlus` before presenting the paywall so
    /// `handlePaywallDismiss` can tell a genuine new purchase apart from a
    /// no-op dismiss.
    private func openPaywall() {
        hadPlusWhenPaywallOpened = PlusEntitlements.shared.hasPlus
        showPaywall = true
    }

    /// Refreshes the member card after the paywall closes, and — only on a
    /// genuine new purchase (ANIMATION_SPEC §4) — shows the "struck in gold"
    /// toast alongside the card's own gold-strike entrance.
    private func handlePaywallDismiss() {
        Task {
            await loadMembershipInfo()
            if !hadPlusWhenPaywallOpened, PlusEntitlements.shared.hasPlus {
                toast = PTToastItem(message: "Your card has been struck in gold.")
            }
        }
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
