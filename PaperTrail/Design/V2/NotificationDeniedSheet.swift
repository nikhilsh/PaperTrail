import SwiftUI

// MARK: - NotificationDeniedSheet (graceful notification permission)
//
// The DENIED-state sheet: shown whenever `NotificationPermissionGate` finds
// `.denied` at a gate site, or an honest row (a reminder toggle left ON, or
// the recall status row) is tapped after permission was revoked. Same
// paper-card language as `SoftAskSheet` — kicker, serif title, primary/
// secondary button pair — but named for what actually happened rather than
// asking again: iOS never re-prompts once denied, so the only path back is
// Settings. No shame, no nagging copy; one sheet per attempt.

struct NotificationDeniedSheet: View {
    let context: AskContext
    var onOpenSettings: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOTIFICATIONS ARE OFF")
                .ptMonoLabel(10, tracking: 2.2)
                .foregroundStyle(PT.goldDeep)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 19))
                    .foregroundStyle(PT.onPaper2)
                    .padding(.top, 3)
                Text("Notifications are off for PaperTrail")
                    .font(PTFont.serif(24, weight: 600))
                    .foregroundStyle(PT.onPaper)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            Text(context.deniedBody)
                .font(.system(size: 14))
                .foregroundStyle(PT.onPaper2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Button(action: onOpenSettings) {
                Text("Open iOS Settings")
            }
            .buttonStyle(PTDarkButtonStyle(fullWidth: true))
            .padding(.top, 18)

            Button(action: onNotNow) {
                Text("NOT NOW")
                    .font(PTFont.mono(10.5, medium: true))
                    .tracking(1.4)
                    .foregroundStyle(PT.onPaper3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .padding(22)
        .paperCard(goldFold: false)
    }
}

#Preview("NotificationDeniedSheet") {
    ZStack {
        PT.inkCanvas.ignoresSafeArea()
        NotificationDeniedSheet(context: .warranty, onOpenSettings: {}, onNotNow: {})
            .padding(14)
    }
}
