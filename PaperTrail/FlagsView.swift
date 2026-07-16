#if !APPSTORE
import SwiftUI
import WidgetKit

/// The v3 flag board — per `docs/design-v3/V3_BRIEF.md` §0 and the V3-3 mock
/// (`docs/design-v3/PaperTrail v3 Screens.html`). Appended to Advanced &
/// Diagnostics, DEBUG & TestFlight-internal builds only: `AdvancedDiagnosticsView`
/// wraps its entry row in `#if !APPSTORE`, and this whole file is wrapped the
/// same way so an APPSTORE build never even compiles a way to flip a flag.
struct FlagsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var refreshToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Flags")
                        .font(PTFont.serif(30, weight: 600))
                        .foregroundStyle(PT.txt)
                }

                banner

                SettingsCard {
                    ForEach(Array(Flag.allCases.enumerated()), id: \.element) { index, flag in
                        if index > 0 { SettingsRowDivider() }
                        FlagRow(flag: flag, refreshToken: refreshToken) { toggledOn in
                            FeatureFlags.setOn(toggledOn, for: flag)
                            // shelfWidgets renders differently depending on
                            // the flag (fallback vs. real content) — nudge
                            // WidgetKit to re-render existing placed
                            // instances immediately rather than waiting for
                            // its own refresh budget (item 10).
                            if flag == .shelfWidgets {
                                WidgetCenter.shared.reloadAllTimelines()
                            }
                            refreshToken += 1
                        }
                    }
                }

                footerActions
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.top, 6)
            .padding(.bottom, 130)
        }
        .ptScreen()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Diagnostics")
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
    }

    private var banner: some View {
        Text("DEBUG & TESTFLIGHT ONLY · COMPILED OUT OF APP STORE BUILDS")
            .ptMonoLabel(9.5, tracking: 2)
            .foregroundStyle(PT.amber)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PT.amber.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
    }

    private var footerActions: some View {
        HStack {
            footerAction("ALL ON", color: PT.gold) {
                FeatureFlags.setAll(true)
                refreshToken += 1
            }
            Spacer()
            footerAction("ALL OFF", color: PT.txt3) {
                FeatureFlags.setAll(false)
                refreshToken += 1
            }
            Spacer()
            footerAction("MATCH APP STORE", color: PT.txt3) {
                // App Store builds are hard-off for every flag — matching
                // that state locally means "all off", same action as ALL OFF.
                FeatureFlags.setAll(false)
                refreshToken += 1
            }
        }
    }

    private func footerAction(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ptMonoLabel(10.5, tracking: 1.4).foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

/// One flag row: mono flag name + plain subtitle, sage toggle bound to the
/// App Group defaults. `refreshToken` forces the row to re-read
/// `FeatureFlags.isOn` after a footer bulk action changes it out from under
/// the row's own toggle binding.
private struct FlagRow: View {
    let flag: Flag
    let refreshToken: Int
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(flag.rawValue)
                    .font(PTFont.mono(12, medium: false))
                    .tracking(0.5)
                    .foregroundStyle(PT.txt)
                Text(flag.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(PT.txt3)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { FeatureFlags.isOn(flag) },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .tint(PT.sage)
            .id(refreshToken)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}
#endif
