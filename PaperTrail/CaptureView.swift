import SwiftUI

struct CaptureView: View {
    var body: some View {
        List {
            Section("Capture") {
                Label("Document scan flow will live here", systemImage: "doc.viewfinder")
                Label("OCR extraction will draft metadata", systemImage: "text.viewfinder")
                Label("Users will confirm before save", systemImage: "checkmark.circle")
            }
        }
        .navigationTitle("Capture")
    }
}

#Preview {
    NavigationStack {
        CaptureView()
    }
}
