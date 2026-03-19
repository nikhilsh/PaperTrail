import SwiftUI
import SwiftData

@main
struct PaperTrailApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView()
        }
        .modelContainer(for: [PurchaseRecord.self, Attachment.self])
    }
}
