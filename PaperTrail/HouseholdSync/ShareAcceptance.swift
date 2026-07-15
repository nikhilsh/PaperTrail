import CloudKit
import UIKit
import UserNotifications

/// The app has no app/scene delegate under the pure SwiftUI lifecycle used
/// elsewhere in PaperTrail. CloudKit share acceptance (tapping a household
/// invite link) is delivered exclusively through `UIApplicationDelegate` /
/// `UIWindowSceneDelegate` callbacks, so this is the one place the app needs
/// a minimal delegate chain — installed via `@UIApplicationDelegateAdaptor`
/// in `PaperTrailApp`. Neither delegate here manages any UI: SwiftUI keeps
/// driving the window/scene exactly as it does today, this file exists only
/// to catch the share-acceptance callback and forward it to
/// `HouseholdManager.acceptShare(metadata:)` (Milestone 4 Phase 2 — see
/// docs/SHARING_ARCHITECTURE.md). It's also the natural home for the other
/// UIKit-only entry points the deep-link spine needs: notification
/// tap-through (`UNUserNotificationCenterDelegate`) and Home Screen quick
/// actions (the scene delegate's `performActionFor` / `connectionOptions`).
final class PaperTrailAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = PaperTrailSceneDelegate.self
        return configuration
    }

    // No application(_:userDidAcceptCloudKitShareWith:) fallback: it's
    // deprecated as of iOS 26 (our minimum target), and in a scene-based app
    // UIKit delivers the UIWindowSceneDelegate callback below instead.
}

// MARK: - Notification tap-through

/// Routes a tapped warranty/return-window notification to its record (§1 —
/// see NotificationManager, which stamps `userInfo["recordID"]` on every
/// request it schedules) and lets notifications banner+sound while the app
/// is foregrounded, which UIKit suppresses by default.
extension PaperTrailAppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let recordIDString = response.notification.request.content.userInfo["recordID"] as? String,
              let recordID = UUID(uuidString: recordIDString) else {
            AppLogger.warn("Notification tapped with no recordID (\(response.notification.request.identifier))", category: "deeplink")
            return
        }
        Task { @MainActor in
            AppRouter.shared.navigate(to: .record(recordID))
        }
    }
}

// MARK: - Home Screen quick actions

/// `UIApplicationShortcutItemType` values — must match `PaperTrail-Info.plist`'s
/// static `UIApplicationShortcutItems`.
enum ShortcutItemType {
    static let scan = "nikhilsh.PaperTrail.scan"
    static let expiringSoon = "nikhilsh.PaperTrail.expiringSoon"
}

/// Exists only to receive `userDidAcceptCloudKitShareWith:` and quick-action
/// callbacks — it must NOT create or manage a `UIWindow`; SwiftUI's
/// `WindowGroup` continues to own the window/scene lifecycle entirely.
final class PaperTrailSceneDelegate: NSObject, UIWindowSceneDelegate {

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        handleShareAcceptance(metadata: cloudKitShareMetadata, source: "scene delegate")
    }

    /// Cold launch via a quick action: the shortcut item arrives in
    /// `connectionOptions` instead of `performActionFor` below. Reads only
    /// `connectionOptions` — never touches `scene.windows` — so SwiftUI's own
    /// window setup is untouched.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcutItem = connectionOptions.shortcutItem {
            handleShortcutItem(shortcutItem, source: "cold launch")
        }
    }

    /// Warm launch via a quick action: the app was already running.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        handleShortcutItem(shortcutItem, source: "quick action")
        completionHandler(true)
    }

    private func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem, source: String) {
        let route: Route?
        switch shortcutItem.type {
        case ShortcutItemType.scan: route = .capture
        case ShortcutItemType.expiringSoon: route = .expiringSoon
        default: route = nil
        }
        guard let route else {
            AppLogger.warn("Unrecognized shortcut item type: \(shortcutItem.type) (\(source))", category: "deeplink")
            return
        }
        Task { @MainActor in
            AppRouter.shared.navigate(to: route)
        }
    }
}

private func handleShareAcceptance(metadata: CKShare.Metadata, source: String) {
    guard HouseholdManager.recordSharingEnabled else {
        // Fix 10: a user hit a dead end tapping a real invite link — this
        // must be self-diagnosing from Sentry, not OSLog-only.
        AppLogger.error("Share link tapped but record sharing disabled (\(source))", category: "cloud.sharing")
        return
    }
    AppLogger.info("Share link tapped, accepting household invite (\(source))", category: "cloud.sharing")
    Task { @MainActor in
        await HouseholdManager.shared.acceptShare(metadata: metadata)
    }
}
