import SwiftUI
import SwiftData

struct RecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allAttachments: [Attachment]
    @Bindable var record: PurchaseRecord
    @State private var showDeleteConfirmation = false
    @State private var selectedImageFilename: SelectedFilename?
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var isExporting = false

    private var attachments: [Attachment] {
        allAttachments.filter { $0.recordID == record.id }
    }

    private var warrantyColor: Color {
        switch record.warrantyStatus {
        case .active: .green
        case .expiringSoon: .orange
        case .expired: .red
        case .unknown: .secondary
        }
    }

    var body: some View {
        List {
            // Header
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(record.productName)
                        .font(.title3.bold())

                    if let merchantName = record.merchantName {
                        Label(merchantName, systemImage: "storefront")
                            .foregroundStyle(.secondary)
                    }

                    if let amount = record.formattedAmount {
                        Text(amount)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.vertical, 4)
            }

            // Warranty & Support
            Section("Warranty & Support") {
                HStack {
                    Text("Warranty status")
                    Spacer()
                    Text(record.warrantyStatus.label)
                        .foregroundStyle(warrantyColor)
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

            // Purchase details
            Section("Purchase") {
                if let purchaseDate = record.purchaseDate {
                    LabeledContent("Purchased") {
                        Text(purchaseDate, format: .dateTime.day().month().year())
                    }
                }

                if let amount = record.formattedAmount {
                    LabeledContent("Amount", value: amount)
                }
            }

            // Organization
            if record.category != nil || !record.tags.isEmpty {
                Section("Organization") {
                    if let category = record.category {
                        LabeledContent("Category", value: category)
                    }

                    if !record.tags.isEmpty {
                        HStack {
                            Text("Tags")
                            Spacer()
                            ForEach(record.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.1), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            // Notes
            if let notes = record.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            // Attachments
            Section("Attachments") {
                if attachments.isEmpty {
                    Text("No attachments")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(attachments) { attachment in
                                Button {
                                    selectedImageFilename = SelectedFilename(attachment.localFilename)
                                } label: {
                                    AttachmentThumbnail(attachment: attachment)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ForEach(attachments) { attachment in
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

            // Delete
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
                HStack(spacing: 16) {
                    Button {
                        Task { await exportRecord() }
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isExporting)

                    NavigationLink {
                        EditRecordView(record: record)
                    } label: {
                        Text("Edit")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                ShareSheetView(activityItems: [shareURL])
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

    private func exportRecord() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let url = try await RecordSharingManager.exportRecord(record, attachments: attachments)
            shareURL = url
            showShareSheet = true
        } catch {
            print("Export failed: \(error)")
        }
    }

    private func deleteRecord() {
        for attachment in attachments {
            ImageStorageManager.delete(attachment.localFilename)
            modelContext.delete(attachment)
        }
        NotificationManager.shared.removeWarrantyReminders(for: record)
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
            if let image = attachment.image {
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
