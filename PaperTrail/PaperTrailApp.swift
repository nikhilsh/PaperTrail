import SwiftUI
import SwiftData
import Sentry
import CloudKit
import UserNotifications

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
    // Respect the user's Diagnostics → "Crash & error reporting" preference
    // (defaults to on). Applies on next launch, which the toggle's subtitle states.
    UserDefaults.standard.register(defaults: ["crashReportingEnabled": true])
    guard UserDefaults.standard.bool(forKey: "crashReportingEnabled") else {
        AppLogger.info("Crash reporting disabled by user preference", category: "observability")
        return
    }

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
        // Structured logs: AppLogger.info/warn forward here so sync flows
        // are diagnosable without waiting for something to crash.
        options.experimental.enableLogs = true
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

/// True when the app process was launched to host a unit test bundle (the
/// standard `XCTestConfigurationFilePath` environment-variable check). The
/// unit test host has no `com.apple.developer.icloud-services` entitlement,
/// and `CKContainer.accountStatus()`/`userRecordID()` don't just error out
/// there — they wedge the whole process indefinitely (reproduced in CI:
/// even a `withThrowingTaskGroup` timeout race around them never resolves).
/// CloudKit preflight is diagnostics-only (Settings/Sentry tags), never
/// required for correctness, so it's skipped entirely under test rather than
/// chased further — the actual sync path (SwiftData's CloudKit-backed
/// `ModelContainer`) is unaffected.
private let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

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

/// Thrown by `withPreflightTimeout` when a CloudKit call doesn't return in
/// time — the CloudKit account-status/user-record calls have no built-in
/// timeout and, observed in CI's un-entitled simulator sandbox (no
/// `com.apple.developer.icloud-services` entitlement on that build), can hang
/// indefinitely rather than erroring. Bounding them here means a stuck check
/// — there or on a real device with a wedged network path — can't silently
/// freeze the rest of the app's launch `.task` forever; it just becomes
/// another failure on the same try/catch paths below.
private struct PreflightTimeout: Error {}

private func withPreflightTimeout<T: Sendable>(
    seconds: Double = 8,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw PreflightTimeout()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

@MainActor
private func runCloudKitPreflight() async {
    let defaults = UserDefaults.standard
    let containerID = AppDiagnostics.cloudKitContainerIdentifier
    defaults.set(containerID, forKey: AppDiagnostics.cloudKitContainerIdentifierKey)

    let container = CKContainer(identifier: containerID)

    do {
        let status = try await withPreflightTimeout { try await container.accountStatus() }
        let statusText = accountStatusDescription(status)
        defaults.set(statusText, forKey: AppDiagnostics.cloudKitAccountStatusKey)
        addStartupBreadcrumb(level: .info, category: "cloudkit.preflight", message: "Account status: \(statusText)")
        SentrySDK.configureScope { scope in scope.setTag(value: statusText, key: "cloudkit_account_status") }

        do {
            _ = try await withPreflightTimeout { try await container.userRecordID() }
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

/// Single source of truth for the app's CloudKit-backed SwiftData store.
///
/// Both `PaperTrailApp.init()` and the App Intents (Siri/Shortcuts, in
/// `PaperTrail/AppIntents/`) need a `ModelContainer` pointing at the exact same
/// store, and App Intents may run in a process the OS launched just to service
/// the intent (no guarantee `PaperTrailApp.init()` ran first in that process).
/// A shared, lazily-created singleton means whichever entry point touches it
/// first builds the one and only container for that process. **Do not**
/// construct a second `ModelConfiguration` anywhere else; route every access
/// through `PaperTrailModelContainer.shared`.
enum PaperTrailModelContainer {
    // Single-store approach: both PurchaseRecord and Attachment live in the same
    // CloudKit-backed store. Attachment holds only lightweight metadata (filename,
    // type, OCR text); actual image blobs stay on-disk via ImageStorageManager.
    // This avoids the multi-configuration + CloudKit bug that causes
    // SwiftDataError.loadIssueModelContainer on iOS 17/18.
    static let schema = Schema([PurchaseRecord.self, Attachment.self, MerchantProfile.self, ProductCategoryMemory.self])

    static let shared: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        let cloudConfig = ModelConfiguration(
            "PaperTrail",
            schema: schema,
            cloudKitDatabase: .automatic
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [cloudConfig])
            UserDefaults.standard.set(SyncBackendState.cloudKit, forKey: SyncBackendState.defaultsKey)
            UserDefaults.standard.removeObject(forKey: SyncBackendState.errorKey)
            addStartupBreadcrumb(level: .info, category: "sync", message: "CloudKit-backed ModelContainer initialized successfully")
            SentrySDK.configureScope { scope in scope.setTag(value: SyncBackendState.cloudKit, key: "sync_backend") }
            return container
        } catch {
            let errorText = String(describing: error)
            UserDefaults.standard.set(SyncBackendState.localFallback, forKey: SyncBackendState.defaultsKey)
            UserDefaults.standard.set(errorText, forKey: SyncBackendState.errorKey)
            addStartupBreadcrumb(level: .error, category: "sync", message: "CloudKit-backed ModelContainer initialization failed")
            AppLogger.error("CloudKit startup fallback: \(errorText)", category: "sync", tags: ["sync_backend": SyncBackendState.localFallback])
            SentrySDK.configureScope { scope in scope.setTag(value: SyncBackendState.localFallback, key: "sync_backend") }

            let localConfig = ModelConfiguration(
                "PaperTrailLocal",
                schema: schema,
                cloudKitDatabase: .none
            )

            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Failed to create local ModelContainer: \(error)")
            }
        }
    }
}

@main
struct PaperTrailApp: App {
    @UIApplicationDelegateAdaptor(PaperTrailAppDelegate.self) private var appDelegate
    let modelContainer: ModelContainer

    init() {
        configureSentry()

        // Register the bundled OFL fonts (Newsreader, IBM Plex Mono) before any
        // view renders so the design-system type is available on first paint.
        PTFont.registerIfNeeded()

        // Copies left behind by a killed/crashed "Open in PaperTrail" import
        // shouldn't accumulate in the temp inbox forever.
        DocumentInbox.purgeAll()

        modelContainer = PaperTrailModelContainer.shared
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(CloudImageSyncManager.shared)
                .reviewPrompting()
                .task {
                    // No-ops entirely while PlusConfig.enabled is false — no
                    // StoreKit call is made.
                    PlusEntitlements.shared.start()
                    // Permission is requested ONLY through the N1 soft-ask
                    // flow (SoftAskCoordinator) while status is undetermined
                    // — an unconditional call here would fire the system
                    // prompt before the soft-ask ever gets a chance to show.
                    // Once the user has answered (either way), re-asserting
                    // here is a harmless no-op (no UI, just re-reads the
                    // existing status), so behavior for already-decided users
                    // is unchanged.
                    //
                    // Graceful notification permission (NotificationPermissionGate):
                    // this `!= .notDetermined` gate must NEVER be loosened or
                    // removed. `NotificationPermissionGate.ensurePermission`
                    // and `SoftAskCoordinator` both assume the system prompt
                    // is only ever triggered from their own explicit ask
                    // sheets while status is `.notDetermined` — if this
                    // launch-time call requested authorization unconditionally,
                    // it would fire the real system prompt before either ask
                    // sheet ever got a chance to show, burning the user's one
                    // shot at the OS prompt on an unexplained launch-time
                    // popup instead of an in-context ask.
                    let notificationStatus = await UNUserNotificationCenter.current()
                        .notificationSettings().authorizationStatus
                    if notificationStatus != .notDetermined {
                        _ = await NotificationManager.shared.requestPermission()
                    }
                    await NotificationManager.shared.migrateIdentifiersIfNeeded(modelContext: modelContainer.mainContext)
                    if !isRunningUnitTests {
                        await runCloudKitPreflight()
                    }
                    await syncCloudImages()
                    // Same un-entitled-test-host deadlock as runCloudKitPreflight
                    // above — HouseholdSyncEngine/HouseholdMirrorCoordinator touch
                    // CloudKit directly on start(). Nothing in the unit test suite
                    // exercises live household sync, so skip starting it there too.
                    if HouseholdManager.recordSharingEnabled, !isRunningUnitTests {
                        addStartupBreadcrumb(level: .info, category: "cloud.sharing", message: "Starting household sync engines at launch")
                        HouseholdSyncEngine.shared.start()
                        HouseholdMirrorCoordinator.shared.start()
                    }
                    await CommunityLearning.shared.refreshCommunityHints()
                    // Drain any corrections/confirmations logged before the
                    // last sync (or before the user opted in at all).
                    await CommunityLearning.shared.syncBacklog()
                    CorrectionLogger.onLearningFeedback = { payload in
                        Task { @MainActor in
                            let service = MerchantLearningService(modelContext: modelContainer.mainContext)
                            service.captureFeedback(payload)
                        }
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    /// On launch, sync images in both directions:
    /// 1. Upload any local images that haven't been pushed to CloudKit yet
    /// 2. Download any images that arrived via metadata sync but lack local files
    @MainActor
    private func syncCloudImages() async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<Attachment>()
        guard let attachments = try? context.fetch(descriptor) else { return }

        let syncInfos = attachments.map {
            AttachmentSyncInfo(id: $0.id, localFilename: $0.localFilename)
        }

        let manager = CloudImageSyncManager.shared

        // Upload first (source device pushes), then download (receiving device pulls)
        await manager.uploadMissingImages(attachments: syncInfos)
        await manager.syncMissingImages(attachments: syncInfos)

        // Record the time of the last successful sync so Settings can show an
        // honest "Backed up · {relativeTime}" instead of a permanent green
        // (§7) — but ONLY when this round actually succeeded. Both calls
        // above run their transfers to completion before returning, so by
        // now `transferErrors` reflects this round's outcome; a non-empty
        // dict means something failed, and stamping "now" anyway would
        // fabricate a "just now" backup that didn't happen (§6).
        guard manager.transferErrors.isEmpty else { return }
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: "lastCloudSyncDate")
    }
}
