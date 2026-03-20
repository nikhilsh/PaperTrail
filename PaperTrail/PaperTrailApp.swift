import SwiftUI
import SwiftData
import Sentry
import CloudKit

private enum SyncBackendState {
    static let defaultsKey = "activeSyncBackend"
    static let errorKey = "cloudKitInitError"
    static let cloudKit = "CloudKit"
    static let localFallback = "Local fallback"
}

private enum AppDiagnostics {
    static let sentryDSNKey = "SENTRY_DSN"
    static let cloudKitContainerIdentifier = "iCloud.nikhilsh.PaperTrail"
    static let cloudKitAccountStatusKey = "cloudKitAccountStatus"
    static let cloudKitContainerStatusKey = "cloudKitContainerStatus"
    static let cloudKitContainerIdentifierKey = "cloudKitContainerIdentifier"
}

private func addStartupBreadcrumb(level: SentryLevel, category: String, message: String) {
    let crumb = Breadcrumb()
    crumb.level = level
    crumb.category = category
    crumb.message = message
    SentrySDK.addBreadcrumb(crumb)
    AppLogger.info(message, category: category)
}

private func configureSentry() {
    let dsn = BuildSecrets.sentryDSN
    guard !dsn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return
    }

    SentrySDK.start { options in
        options.dsn = dsn
        options.debug = false
        options.enableCaptureFailedRequests = true
        options.enableAutoSessionTracking = true
        options.attachScreenshot = false
    }

    AppLogger.info("Sentry initialized", category: "observability")

    let info = Bundle.main.infoDictionary ?? [:]
    if let version = info["CFBundleShortVersionString"] as? String {
        SentrySDK.configureScope { scope in scope.setTag(value: version, key: "app_version") }
    }
    if let build = info["CFBundleVersion"] as? String {
        SentrySDK.configureScope { scope in scope.setTag(value: build, key: "build_number") }
    }

    addStartupBreadcrumb(level: .info, category: "app.lifecycle", message: "PaperTrail launch started")
}

private func accountStatusDescription(_ status: CKAccountStatus) -> String {
    switch status {
    case .available: return "Available"
    case .noAccount: return "No iCloud account"
    case .restricted: return "Restricted"
    case .couldNotDetermine: return "Could not determine"
    case .temporarilyUnavailable: return "Temporarily unavailable"
    @unknown default: return "Unknown"
    }
}

@MainActor
private func runCloudKitPreflight() async {
    let defaults = UserDefaults.standard
    let containerID = AppDiagnostics.cloudKitContainerIdentifier
    defaults.set(containerID, forKey: AppDiagnostics.cloudKitContainerIdentifierKey)

    let container = CKContainer(identifier: containerID)

    do {
        let status = try await container.accountStatus()
        let statusText = accountStatusDescription(status)
        defaults.set(statusText, forKey: AppDiagnostics.cloudKitAccountStatusKey)
        addStartupBreadcrumb(level: .info, category: "cloudkit.preflight", message: "Account status: \(statusText)")
        SentrySDK.configureScope { scope in scope.setTag(value: statusText, key: "cloudkit_account_status") }

        do {
            _ = try await container.userRecordID()
            defaults.set("User record lookup succeeded", forKey: AppDiagnostics.cloudKitContainerStatusKey)
            addStartupBreadcrumb(level: .info, category: "cloudkit.preflight", message: "User record lookup succeeded for \(containerID)")
        } catch {
            let errorText = String(describing: error)
            defaults.set("User record lookup failed: \(errorText)", forKey: AppDiagnostics.cloudKitContainerStatusKey)
            addStartupBreadcrumb(level: .error, category: "cloudkit.preflight", message: "User record lookup failed for \(containerID)")
            AppLogger.error("CloudKit preflight userRecordID failure: \(errorText)", category: "cloudkit.preflight", tags: ["container": containerID])
        }
    } catch {
        let errorText = String(describing: error)
        defaults.set("Account status failed: \(errorText)", forKey: AppDiagnostics.cloudKitAccountStatusKey)
        defaults.set("Preflight failed before user record lookup: \(errorText)", forKey: AppDiagnostics.cloudKitContainerStatusKey)
        addStartupBreadcrumb(level: .error, category: "cloudkit.preflight", message: "Account status failed for \(containerID)")
        AppLogger.error("CloudKit preflight accountStatus failure: \(errorText)", category: "cloudkit.preflight", tags: ["container": containerID])
    }
}

@main
struct PaperTrailApp: App {
    @State private var authManager = AuthenticationManager()
    let modelContainer: ModelContainer

    init() {
        configureSentry()

        let fullSchema = Schema([PurchaseRecord.self, Attachment.self])
        let cloudRecordsSchema = Schema([PurchaseRecord.self])
        let localAttachmentsSchema = Schema([Attachment.self])

        let cloudConfig = ModelConfiguration(
            "PaperTrailCloud",
            schema: cloudRecordsSchema,
            cloudKitDatabase: .automatic
        )
        let localAttachmentsConfig = ModelConfiguration(
            "PaperTrailLocalAttachments",
            schema: localAttachmentsSchema,
            cloudKitDatabase: .none
        )

        do {
            modelContainer = try ModelContainer(
                for: fullSchema,
                configurations: [cloudConfig, localAttachmentsConfig]
            )
            UserDefaults.standard.set(SyncBackendState.cloudKit, forKey: SyncBackendState.defaultsKey)
            UserDefaults.standard.removeObject(forKey: SyncBackendState.errorKey)
            addStartupBreadcrumb(level: .info, category: "sync", message: "CloudKit-backed ModelContainer initialized successfully")
            SentrySDK.configureScope { scope in scope.setTag(value: SyncBackendState.cloudKit, key: "sync_backend") }
        } catch {
            let errorText = String(describing: error)
            UserDefaults.standard.set(SyncBackendState.localFallback, forKey: SyncBackendState.defaultsKey)
            UserDefaults.standard.set(errorText, forKey: SyncBackendState.errorKey)
            addStartupBreadcrumb(level: .error, category: "sync", message: "CloudKit-backed ModelContainer initialization failed")
            AppLogger.error("CloudKit startup fallback: \(errorText)", category: "sync", tags: ["sync_backend": SyncBackendState.localFallback])
            SentrySDK.configureScope { scope in scope.setTag(value: SyncBackendState.localFallback, key: "sync_backend") }

            let localRecordsConfig = ModelConfiguration(
                "PaperTrailLocalRecords",
                schema: cloudRecordsSchema,
                cloudKitDatabase: .none
            )
            let localAttachmentsFallbackConfig = ModelConfiguration(
                "PaperTrailLocalAttachments",
                schema: localAttachmentsSchema,
                cloudKitDatabase: .none
            )

            do {
                modelContainer = try ModelContainer(
                    for: fullSchema,
                    configurations: [localRecordsConfig, localAttachmentsFallbackConfig]
                )
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
                    await runCloudKitPreflight()
                }
        }
        .modelContainer(modelContainer)
    }
}
