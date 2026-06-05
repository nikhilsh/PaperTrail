import SwiftUI

/// "Your household." — Family Sharing screen (§5). Fleshed out in its own PR;
/// this scaffold keeps the Settings navigation stable.
struct HouseholdView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ComingSoonScreen(
            backTitle: "Settings",
            title: "Your",
            accent: "household.",
            blurb: "Shared things deserve shared proof — everyone covered on their own phone.",
            note: "Family sharing is coming together.",
            dismiss: dismiss
        )
    }
}

/// A small placeholder screen matching the design system, used by features still
/// being built out in subsequent PRs.
struct ComingSoonScreen: View {
    let backTitle: String
    let title: String
    let accent: String
    let blurb: String
    let note: String
    let dismiss: DismissAction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                (Text(title + " ").foregroundStyle(PT.txt)
                 + Text(accent).foregroundStyle(PT.goldHi))
                    .font(PTFont.serif(34, weight: 600))
                Text(blurb)
                    .font(.system(size: 14))
                    .foregroundStyle(PT.txt2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Image(systemName: "hammer.fill").foregroundStyle(PT.gold)
                    Text(note).font(.system(size: 13)).foregroundStyle(PT.txt2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xE7DCC4, alpha: 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PT.hair, lineWidth: 1))
                .padding(.top, 8)
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .ptScreen()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(backTitle)
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(PT.txt2)
                }
            }
        }
    }
}
