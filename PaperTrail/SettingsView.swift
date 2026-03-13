import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section("Storage") {
                LabeledContent("Persistence", value: "Local first")
                LabeledContent("Sync", value: "CloudKit planned")
            }

            Section("Build status") {
                LabeledContent("Current milestone", value: "Milestone 1")
                LabeledContent("Focus", value: "Shell and capture flow")
            }

            Section("Next") {
                Text("Wire real repositories")
                Text("Add scan and OCR flow")
                Text("Persist searchable purchase records")
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
