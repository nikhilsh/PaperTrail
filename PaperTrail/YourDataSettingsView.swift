import SwiftUI
import SwiftData

/// "Your data" (v2 Settings front desk, S1 §4) — the drill-in one level
/// below Settings' top-level "Your data" row. Export, import and the privacy
/// toggles moved verbatim from the old top-level Settings surface.
struct YourDataSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CommunityLearning.optOutKey) private var communityLearningEnabled = false
    @AppStorage("spotlightIndexingEnabled") private var spotlightIndexingEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(Text("Your data,\n").foregroundStyle(PT.txt))\(Text("yours.").foregroundStyle(PT.goldHi))")
                        .font(PTFont.serif(30, weight: 600))
                    Text("Export, import, and exactly what stays private — no lock-in, ever.")
                        .font(.system(size: 14))
                        .foregroundStyle(PT.txt2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

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
        YourDataSettingsView()
    }
    .tint(PT.gold)
    .preferredColorScheme(.dark)
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
