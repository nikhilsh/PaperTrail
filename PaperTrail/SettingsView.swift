import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section("PaperTrail") {
                LabeledContent("Version", value: "Milestone 1")
                LabeledContent("Storage", value: "Local first")
                LabeledContent("Sync", value: "CloudKit later")
            }

            Section("Next") {
                Text("Wire repositories and persistence")
                Text("Replace placeholders with real capture flow")
                Text("Add OCR-assisted extraction")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
