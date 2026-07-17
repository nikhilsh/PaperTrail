import SwiftUI

/// "Reminders" (v2 Settings front desk, S1 §2) — the drill-in one level
/// below Settings' top-level "Reminders" row. Every row here previously
/// lived directly on the Settings surface; moved verbatim, copy unchanged.
struct RemindersSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let reminders = ReminderSettings.shared
    private var gate = NotificationPermissionGate.shared

    /// Honest-states rule (graceful notification permission, item 5): once
    /// the system has actually denied notifications, a toggle left ON is a
    /// lie unless the row says so. Doesn't fight the user's intent by
    /// flipping the toggle back — only the label changes.
    private var isDenied: Bool { gate.lastKnownAuthorizationStatus == .denied }

    var body: some View {
        @Bindable var reminders = reminders

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(Text("Reminders,\n").foregroundStyle(PT.txt))\(Text("on your terms.").foregroundStyle(PT.goldHi))")
                        .font(PTFont.serif(30, weight: 600))
                    Text("A butler's voice, not a marketer's. We only knock when there's something worth knowing.")
                        .font(.system(size: 14))
                        .foregroundStyle(PT.txt2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                SettingsCard {
                    SettingsRow(
                        icon: "bell", iconColor: PT.gold, title: "Warranty reminders",
                        subtitle: warrantySubtitle, subtitleColor: warrantyHonestlyDenied ? PT.amber : PT.txt3,
                        toggle: $reminders.warrantyRemindersEnabled,
                        onRowTap: warrantyHonestlyDenied ? { gate.presentDeniedDirectly(context: .warranty) } : nil
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
                        subtitle: returnWindowSubtitle, subtitleColor: returnWindowHonestlyDenied ? PT.amber : PT.txt3,
                        toggle: $reminders.returnWindowRemindersEnabled,
                        onRowTap: returnWindowHonestlyDenied ? { gate.presentDeniedDirectly(context: .warranty) } : nil
                    )
                    SettingsRowDivider()
                    SettingsRow(
                        icon: "calendar.badge.clock", iconColor: PT.gold, title: "Monthly coverage digest",
                        subtitle: digestSubtitle, subtitleColor: digestHonestlyDenied ? PT.amber : PT.txt3,
                        toggle: $reminders.digestEnabled,
                        onRowTap: digestHonestlyDenied ? { gate.presentDeniedDirectly(context: .digest) } : nil
                    )
                    SettingsRowDivider()
                    SettingsRow(
                        icon: "sparkles", iconColor: PT.gold, title: "Suggest support contacts",
                        subtitle: "Look up brand help lines when something breaks",
                        toggle: $reminders.suggestSupportContacts
                    )
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
                        Text("Settings")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
        .task {
            // Refreshes `isDenied` against the real current status on every
            // appearance — the last observation could be stale if the user
            // changed it in Settings and came straight back to this screen
            // rather than foregrounding the app root first.
            await gate.refreshAuthorizationStatus()
        }
        // Item 4: on toggle ON, funnel through the gate before trusting the
        // setting. A "Not now"/denied response leaves the toggle ON — the
        // user's intent is real — the honest subtitle above is what tells
        // the truth instead.
        .onChange(of: reminders.warrantyRemindersEnabled) { wasOn, isOn in
            guard isOn, !wasOn else { return }
            Task { await gate.ensurePermission(context: .warranty) }
        }
        .onChange(of: reminders.returnWindowRemindersEnabled) { wasOn, isOn in
            guard isOn, !wasOn else { return }
            Task { await gate.ensurePermission(context: .warranty) }
        }
        .onChange(of: reminders.digestEnabled) { wasOn, isOn in
            guard isOn, !wasOn else { return }
            Task { await gate.ensurePermission(context: .digest) }
        }
    }

    // MARK: Honest rows (item 5)

    private var warrantyHonestlyDenied: Bool { isDenied && reminders.warrantyRemindersEnabled }
    private var warrantySubtitle: String {
        guard reminders.warrantyRemindersEnabled else { return "Off — you won't be warned" }
        return isDenied ? "Off in iOS Settings — notifications can't reach you" : "Before each warranty runs out"
    }

    private var returnWindowHonestlyDenied: Bool { isDenied && reminders.returnWindowRemindersEnabled }
    private var returnWindowSubtitle: String {
        returnWindowHonestlyDenied ? "Off in iOS Settings — notifications can't reach you" : "Warn before a return or refund period closes"
    }

    private var digestHonestlyDenied: Bool { isDenied && reminders.digestEnabled }
    private var digestSubtitle: String {
        digestHonestlyDenied ? "Off in iOS Settings — notifications can't reach you" : "One summary of what's expiring and closing"
    }
}

#Preview {
    NavigationStack {
        RemindersSettingsView()
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
}
