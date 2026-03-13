import SwiftUI

struct CaptureView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add proof of purchase")
                    .font(.title2.bold())

                Text("Capture now, search later.")
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    NavigationLink {
                        DraftRecordView(seedType: .receipt)
                    } label: {
                        CaptureActionRow(
                            title: "Scan receipt",
                            subtitle: "For printed receipts and in-store purchases.",
                            systemImage: "doc.viewfinder"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DraftRecordView(seedType: .warranty)
                    } label: {
                        CaptureActionRow(
                            title: "Add warranty card",
                            subtitle: "Attach warranty proof to the product record.",
                            systemImage: "shield.lefthalf.filled"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DraftRecordView(seedType: .other)
                    } label: {
                        CaptureActionRow(
                            title: "Import photo",
                            subtitle: "Use an existing image from your library.",
                            systemImage: "photo.on.rectangle"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text("PaperTrail will extract text, let you confirm the key fields, and save everything as a searchable record.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Capture")
    }
}

private struct CaptureActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        CaptureView()
            .environmentObject(PurchaseRecordStore())
    }
}
