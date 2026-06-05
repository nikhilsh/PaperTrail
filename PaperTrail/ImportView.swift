import SwiftUI

/// "Bring it all in." — bulk backfill screen (§4). Fleshed out in its own PR;
/// this scaffold keeps the Settings navigation stable.
struct ImportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ComingSoonScreen(
            backTitle: "Settings",
            title: "Bring it",
            accent: "all in.",
            blurb: "We read each one on-device and let you confirm before saving.",
            note: "Import is coming together.",
            dismiss: dismiss
        )
    }
}
