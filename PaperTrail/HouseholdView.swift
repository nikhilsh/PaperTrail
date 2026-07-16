import SwiftUI
import SwiftData
import CloudKit

/// "Your household." (§5) — shared things deserve shared proof. Presents the
/// household roster, a real CKShare invite (via UICloudSharingController), and
/// what the household can see. Cross-account record visibility (zone sharing) is
/// gated behind `HouseholdManager.recordSharingEnabled` until it's device-verified.
struct HouseholdView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [PurchaseRecord]

    private var manager = HouseholdManager.shared
    private var cache = HouseholdCache.shared
    private let reminders = ReminderSettings.shared

    /// True when this device joined someone else's household. The "what they
    /// can see" card and its whole-library toggle control the OWNER's
    /// mirroring — showing them to a member rendered "All 0 records" (the
    /// member's own empty library) on Vanessa's phone.
    private var isMemberDevice: Bool { !manager.isHouseholdOwner && !manager.members.isEmpty }

    @AppStorage("household.shareWholeLibrary") private var shareWholeLibrary = true
    @State private var preparing = false
    @State private var sharePrep: SharePresentation?
    @State private var errorMessage: String?
    /// Set when `makeShare()` throws `HouseholdError.plusRequired` — shows
    /// the paywall instead of the generic error alert. Flag-gated at the
    /// source (`PlusConfig.enabled`), so this never fires while off.
    @State private var showPaywall = false

    private var displayMembers: [HouseholdMember] {
        if !manager.members.isEmpty {
            return manager.members.sorted { lhs, rhs in
                roleOrder(lhs.role) < roleOrder(rhs.role)
            }
        }
        return [HouseholdMember(id: "you",
                                name: "You",
                                email: nil,
                                role: .owner)]
    }

    var body: some View {
        @Bindable var reminders = reminders

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(Text("Your\n").foregroundStyle(PT.txt))\(Text("household.").foregroundStyle(PT.goldHi))")
                        .font(PTFont.serif(34, weight: 600))
                    Text("The fridge, the TV, the sofa — shared things, shared proof. Everyone in your home stays covered, on their own phone.")
                        .font(.system(size: 14))
                        .foregroundStyle(PT.txt2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                membersCard

                // A member tapping "Invite" would create their OWN zone/share —
                // wrong, invites only make sense from the owner. Stays visible
                // on the plain flag-off decoy path (isHouseholdOwner defaults
                // true there — see HouseholdManager).
                if manager.isHouseholdOwner || manager.members.isEmpty {
                    Button { Task { await invite() } } label: {
                        HStack(spacing: 8) {
                            if preparing { ProgressView().tint(PT.inkStamp) }
                            Label("Invite a household member", systemImage: "person.badge.plus")
                        }
                    }
                    .buttonStyle(PTGoldButtonStyle())
                    .disabled(preparing)
                }

                if isMemberDevice {
                    memberSharedCard
                } else {
                    whatTheySeeCard(reminders: reminders)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(PT.txt3)
                    Text(isMemberDevice
                         ? "Shared securely through iCloud — you can view your household's records, and only the owner can remove them or end sharing."
                         : "Shared securely through iCloud — members sign in with their own Apple ID. They can view and add, but only you can remove records or end sharing.")
                        .font(.system(size: 12))
                        .foregroundStyle(PT.txt3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !HouseholdManager.recordSharingEnabled {
                    Text("Invites set up your household now. Syncing each other's records across accounts is rolling out next.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(PT.amber)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.bottom, 130)
        }
        .ptScreen()
        .navigationBarBackButtonHidden()
        .task { await manager.refresh() }
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
        .sheet(item: $sharePrep, onDismiss: { Task { await manager.refresh() } }) { prep in
            CloudSharingController(share: prep.share, container: prep.container)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PaywallView() }
                .tint(PT.gold)
                .preferredColorScheme(.dark)
        }
        .alert("Couldn't start sharing", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var membersCard: some View {
        VStack(spacing: 0) {
            Text("MEMBERS")
                .ptMonoLabel(9.5, tracking: 2.4)
                .foregroundStyle(PT.onPaper3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

            ForEach(Array(displayMembers.enumerated()), id: \.element.id) { index, member in
                if index > 0 { Rectangle().fill(PT.onPaperHair).frame(height: 1) }
                memberRow(member)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: false)
    }

    private func memberRow(_ member: HouseholdMember) -> some View {
        HStack(spacing: 12) {
            PTAvatar(initials: member.name.ptInitials, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(PTFont.serif(17, weight: 600))
                    .foregroundStyle(PT.onPaper)
                Text(subtitle(for: member))
                    .font(.system(size: 12))
                    .foregroundStyle(PT.onPaper2)
            }
            Spacer(minLength: 8)
            Text(badge(for: member.role))
                .font(PTFont.mono(9, medium: true))
                .tracking(1.2)
                .foregroundStyle(member.role == .invited ? PT.amber : PT.onPaper3)
        }
        .padding(.vertical, 11)
    }

    private var memberSharedCard: some View {
        VStack(spacing: 0) {
            SettingsSectionLabel(text: "Shared with you")
            SettingsCard {
                SettingsRow(icon: "books.vertical", iconColor: PT.gold,
                            title: "Household records",
                            subtitle: cache.purchaseRecords.isEmpty
                                ? "Nothing shared yet — records appear here as your household adds them"
                                : "\(cache.purchaseRecords.count) shared record\(cache.purchaseRecords.count == 1 ? "" : "s") — in your Library under “Shared with me”")
            }
        }
    }

    private func whatTheySeeCard(reminders: ReminderSettings) -> some View {
        VStack(spacing: 0) {
            SettingsSectionLabel(text: "What they can see")
            SettingsCard {
                SettingsRow(icon: "books.vertical", iconColor: PT.gold,
                            title: "Share my whole library",
                            subtitle: "All \(records.count) records, proof & warranties",
                            toggle: Binding(
                                get: {
                                    // Fix 9: once record sharing is on, the
                                    // zone-resident settings record is
                                    // authoritative if it's arrived — a
                                    // per-device toggle must never silently
                                    // override another device's choice.
                                    // Flag off stays byte-identical to before.
                                    HouseholdManager.recordSharingEnabled
                                        ? (HouseholdCache.shared.shareWholeLibrarySetting ?? shareWholeLibrary)
                                        : shareWholeLibrary
                                },
                                set: { newValue in
                                    shareWholeLibrary = newValue
                                    // shareWholeLibraryChanged no-ops when the
                                    // flag is off, same as the bare
                                    // reconcile() call it replaces.
                                    HouseholdMirrorCoordinator.shared.shareWholeLibraryChanged(newValue)
                                }
                            ))
                SettingsRowDivider()
                SettingsRow(icon: "bell", iconColor: PT.gold,
                            title: "Send reminders to everyone",
                            subtitle: "Each member gets their own expiry alerts",
                            toggle: Binding(get: { reminders.shareRemindersWithHousehold },
                                            set: { reminders.shareRemindersWithHousehold = $0 }))
            }
        }
    }

    // MARK: Actions

    private func invite() async {
        preparing = true
        defer { preparing = false }
        do {
            let (share, container) = try await manager.makeShare()
            sharePrep = SharePresentation(share: share, container: container)
        } catch let error as HouseholdError {
            if case .plusRequired = error {
                showPaywall = true
            } else {
                errorMessage = error.errorDescription ?? error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func roleOrder(_ role: HouseholdRole) -> Int {
        switch role { case .owner: 0; case .member: 1; case .invited: 2 }
    }

    private func subtitle(for member: HouseholdMember) -> String {
        switch member.role {
        case .owner: member.email ?? "Owner"
        case .member: "Can view & add records"
        case .invited: "Invite sent · waiting to join"
        }
    }

    private func badge(for role: HouseholdRole) -> String {
        switch role { case .owner: "OWNER"; case .member: "MEMBER"; case .invited: "INVITED" }
    }
}

/// Identifiable wrapper so the share sheet can be presented via `.sheet(item:)`.
struct SharePresentation: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// UIKit bridge for the system CloudKit sharing UI.
struct CloudSharingController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        // System UI we can't restyle wholesale — but the app's identity is
        // fixed warm-dark (PTTheme), so pin the sheet dark and tint its
        // controls gold instead of leaving stock blue-on-whatever-mode.
        controller.overrideUserInterfaceStyle = .dark
        controller.view.tintColor = UIColor(PT.gold)
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    /// Without a delegate, a failed save inside the sheet (remove
    /// participant, stop sharing) is swallowed whole — the row just stays
    /// and nothing reaches Sentry. The refreshes keep our roster in step
    /// with whatever the sheet actually persisted.
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for csc: UICloudSharingController) -> String? {
            HouseholdManager.shareTitle
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            HouseholdManager.shareThumbnailData()
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            AppLogger.error("Share sheet failed to save share changes: \(error.localizedDescription)", category: "cloud.sharing")
            Task { await HouseholdManager.shared.refresh() }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            AppLogger.info("Share sheet saved share changes", category: "cloud.sharing")
            Task { await HouseholdManager.shared.refresh() }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            AppLogger.info("Share sheet stopped sharing", category: "cloud.sharing")
            Task { await HouseholdManager.shared.refresh() }
        }
    }
}
