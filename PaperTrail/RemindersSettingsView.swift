import SwiftUI

/// "Reminders" (v2 Settings front desk, S1 §2) — the drill-in one level
/// below Settings' top-level "Reminders" row. Every row here previously
/// lived directly on the Settings surface; moved verbatim, copy unchanged.
struct RemindersSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let reminders = ReminderSettings.shared

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
    }
}

#Preview {
    NavigationStack {
        RemindersSettingsView()
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
}
