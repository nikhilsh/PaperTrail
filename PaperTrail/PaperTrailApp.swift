import SwiftUI
import SwiftData

@main
struct PaperTrailApp: App {
    @State private var authManager = AuthenticationManager()
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([PurchaseRecord.self, Attachment.self])
        let cloudConfig = ModelConfiguration(
            "PaperTrail",
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            print("⚠️ CloudKit ModelContainer failed: \(error). Falling back to local-only storage.")

            let localConfig = ModelConfiguration(
                "PaperTrail",
                schema: schema,
                cloudKitDatabase: .none
            )

            do {
                modelContainer = try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Failed to create local ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(authManager)
                .task {
                    _ = await NotificationManager.shared.requestPermission()
                    await authManager.checkCredentialState()
                }
        }
        .modelContainer(modelContainer)
    }
}
