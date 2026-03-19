import SwiftUI
import SwiftData

@main
struct PaperTrailApp: App {
    @State private var authManager = AuthenticationManager()
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([PurchaseRecord.self, Attachment.self])
        let config = ModelConfiguration(
            "PaperTrail",
            schema: schema,
            cloudKitDatabase: .automatic
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(authManager)
                .task {
                    await NotificationManager.shared.requestPermission()
                    await authManager.checkCredentialState()
                }
        }
        .modelContainer(modelContainer)
    }
}
