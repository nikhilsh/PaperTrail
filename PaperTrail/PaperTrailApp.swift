import SwiftUI
import SwiftData
import Sentry

private enum SyncBackendState {
    static let defaultsKey = "activeSyncBackend"
    static let errorKey = "cloudKitInitError"
    static let cloudKit = "CloudKit"
    static let localFallback = "Local fallback"
}

private enum AppDiagnostics {
    static let sentryDSNKey = "SENTRY_DSN"
}

private func addStartupBreadcrumb(level: SentryLevel, category: String, message: String) {
    let crumb = Breadcrumb()
    crumb.level = level
    crumb.category = category
    crumb.message = message
    SentrySDK.addBreadcrumb(crumb)
}

private func configureSentry() {
    guard let dsn = Bundle.main.object(forInfoDictionaryKey: AppDiagnostics.sentryDSNKey) as? String,
          !dsn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
    }

    SentrySDK.start { options in
        options.dsn = dsn
        options.debug = false
        options.enableCaptureFailedRequests = true
        options.enableAutoSessionTracking = true
        options.attachScreenshot = false
    }

    let info = Bundle.main.infoDictionary ?? [:]
    if let version = info["CFBundleShortVersionString"] as? String {
        SentrySDK.setTag(value: version, key: "app_version")
    }
    if let build = info["CFBundleVersion"] as? String {
        SentrySDK.setTag(value: build, key: "build_number")
    }

    addStartupBreadcrumb(level: .info, category: "app.lifecycle", message: "PaperTrail launch started")
}

@main
struct PaperTrailApp: App {
    @State private var authManager = AuthenticationManager()
    let modelContainer: ModelContainer

    init() {
        configureSentry()

        let schema = Schema([PurchaseRecord.self, Attachment.self])
        let cloudConfig = ModelConfiguration(
            "PaperTrail",
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
            UserDefaults.standard.set(SyncBackendState.cloudKit, forKey: SyncBackendState.defaultsKey)
            UserDefaults.standard.removeObject(forKey: SyncBackendState.errorKey)
            addStartupBreadcrumb(level: .info, category: "sync", message: "CloudKit-backed ModelContainer initialized successfully")
            SentrySDK.setTag(value: SyncBackendState.cloudKit, key: "sync_backend")
        } catch {
            let errorText = String(describing: error)
            print("⚠️ CloudKit ModelContainer failed: \(errorText). Falling back to local-only storage.")
            UserDefaults.standard.set(SyncBackendState.localFallback, forKey: SyncBackendState.defaultsKey)
            UserDefaults.standard.set(errorText, forKey: SyncBackendState.errorKey)
            addStartupBreadcrumb(level: .error, category: "sync", message: "CloudKit-backed ModelContainer initialization failed")
            SentrySDK.capture(message: "CloudKit startup fallback: \(errorText)")
            SentrySDK.setTag(value: SyncBackendState.localFallback, key: "sync_backend")

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
