import SwiftUI

struct CaptureView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Capture purchase proof")
                        .font(.title2.bold())
                    Text("Scan a receipt or warranty card now, then find it instantly later.")
                        .foregroundStyle(.secondary)
                }

                CaptureActionCard(
                    title: "Scan receipt",
                    subtitle: "Best for in-store purchases and printed receipts.",
                    systemImage: "receipt"
                )

                CaptureActionCard(
                    title: "Add warranty card",
                    subtitle: "Keep warranty proof attached to the product record.",
                    systemImage: "shield.lefthalf.filled"
                )

                CaptureActionCard(
                    title: "Import existing photo",
                    subtitle: "Useful when the receipt is already in Photos.",
                    systemImage: "photo.on.rectangle"
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("What happens next")
                        .font(.headline)
                    Label("OCR extracts useful text", systemImage: "text.viewfinder")
                    Label("You confirm the important fields", systemImage: "checkmark.circle")
                    Label("PaperTrail saves it as a searchable product record", systemImage: "tray.full")
                }
                .padding(18)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Capture")
    }
}

private struct CaptureActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        CaptureView()
    }
}
