import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var records: [PurchaseRecord]
    @Query private var attachments: [Attachment]

    private var totalImageSize: String {
        let totalBytes = attachments.reduce(into: 0) { total, attachment in
            let url = ImageStorageManager.url(for: attachment.localFilename)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            total += size
        }
        return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    var body: some View {
        List {
            Section("Storage") {
                LabeledContent("Records", value: "\(records.count)")
                LabeledContent("Attachments", value: "\(attachments.count)")
                LabeledContent("Image storage", value: totalImageSize)
                LabeledContent("Persistence", value: "SwiftData (local)")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }

            Section("Milestone") {
                LabeledContent("Current", value: "Milestone 2")
                LabeledContent("Focus", value: "SwiftData + VisionKit + OCR")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
