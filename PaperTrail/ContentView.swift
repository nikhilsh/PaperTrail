import SwiftUI
import SwiftData

/// Legacy placeholder — retained for Xcode file consistency.
/// The actual root view is AppShellView, launched from PaperTrailApp.
struct ContentView: View {
    var body: some View {
        AppShellView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
