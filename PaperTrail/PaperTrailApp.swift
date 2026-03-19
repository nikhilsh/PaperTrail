import SwiftUI
import SwiftData

@main
struct PaperTrailApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView()
                .task {
                    await NotificationManager.shared.requestPermission()
                }
        }
        .modelContainer(for: [PurchaseRecord.self, Attachment.self])
    }
}
