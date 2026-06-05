import SwiftUI

/// "Your data, yours." — full-export screen (§3). Fleshed out in its own PR;
/// this scaffold keeps the Settings navigation stable.
struct ExportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ComingSoonScreen(
            backTitle: "Settings",
            title: "Your data,",
            accent: "yours.",
            blurb: "Take a full copy with you anytime — no lock-in.",
            note: "Export is coming together.",
            dismiss: dismiss
        )
    }
}
