import SwiftUI
import SwiftData

struct RecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var record: PurchaseRecord
    @State private var showDeleteConfirmation = false
    @State private var selectedImageFilename: SelectedFilename?

    private var warrantyStatusText: String {
        guard let exp = record.warrantyExpiryDate else { return "Unknown" }
        return exp >= .now ? "Likely active" : "Likely expired"
    }

    private var warrantyStatusColor: Color {
        guard let exp = record.warrantyExpiryDate else { return .secondary }
        if exp < .now { return .red }
        let cutoff = Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now
        return exp <= cutoff ? .orange : .green
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(record.productName)
                        .font(.title3.bold())

                    if let merchantName = record.merchantName {
                        Label(merchantName, systemImage: "storefront")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Warranty & Support") {
                HStack {
                    Text("Warranty status")
                    Spacer()
                    Text(warrantyStatusText)
                        .foregroundStyle(warrantyStatusColor)
                        .fontWeight(.medium)
                }

                if let exp = record.warrantyExpiryDate {
                    LabeledContent("Warranty until") {
                        Text(exp, format: .dateTime.day().month().year())
                    }
                }

                if let info = record.supportInfo {
                    LabeledContent("Service contact", value: info.phoneNumber)
                    LabeledContent("Source", value: info.confidence == .verified ? "Verified" : "Best guess")

                    if let note = info.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No support contact saved yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Purchase") {
                if let purchaseDate = record.purchaseDate {
                    LabeledContent("Purchased") {
                        Text(purchaseDate, format: .dateTime.day().month().year())
                    }
                }
            }

            if let notes = record.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            Section("Attachments") {
                if record.attachments.isEmpty {
                    Text("No attachments")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(record.attachments) { attachment in
                                Button {
                                    selectedImageFilename = SelectedFilename(attachment.localFilename)
                                } label: {
                                    AttachmentThumbnail(attachment: attachment)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ForEach(record.attachments) { attachment in
                        if let ocrText = attachment.ocrText, !ocrText.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(attachment.type.rawValue.capitalized)
                                    .font(.caption.weight(.semibold))
                                Text(ocrText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Delete Record", role: .destructive) {
                    showDeleteConfirmation = true
                }
            }
        }
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    EditRecordView(record: record)
                } label: {
                    Text("Edit")
                }
            }
        }
        .confirmationDialog("Delete this record?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteRecord()
            }
        } message: {
            Text("This will permanently remove the record and its attachments.")
        }
        .fullScreenCover(item: $selectedImageFilename) { selected in
            ImageViewerView(filename: selected.value)
        }
    }

    private func deleteRecord() {
        // Clean up stored images
        for attachment in record.attachments {
            ImageStorageManager.delete(attachment.localFilename)
        }
        modelContext.delete(record)
        dismiss()
    }
}

/// Wrapper to make a filename Identifiable for sheet presentation.
struct SelectedFilename: Identifiable {
    let id = UUID()
    let value: String
    init(_ value: String) { self.value = value }
}

// MARK: - Subviews

private struct AttachmentThumbnail: View {
    let attachment: Attachment

    var body: some View {
        Group {
            if let image = ImageStorageManager.load(attachment.localFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "doc.questionmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 70, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}

#Preview {
    NavigationStack {
        Text("Preview requires SwiftData context")
    }
}
