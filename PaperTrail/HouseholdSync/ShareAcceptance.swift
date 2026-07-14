import CloudKit
import UIKit

/// The app has no app/scene delegate under the pure SwiftUI lifecycle used
/// elsewhere in PaperTrail. CloudKit share acceptance (tapping a household
/// invite link) is delivered exclusively through `UIApplicationDelegate` /
/// `UIWindowSceneDelegate` callbacks, so this is the one place the app needs
/// a minimal delegate chain — installed via `@UIApplicationDelegateAdaptor`
/// in `PaperTrailApp`. Neither delegate here manages any UI: SwiftUI keeps
/// driving the window/scene exactly as it does today, this file exists only
/// to catch the share-acceptance callback and forward it to
/// `HouseholdManager.acceptShare(metadata:)` (Milestone 4 Phase 2 — see
/// docs/SHARING_ARCHITECTURE.md).
final class PaperTrailAppDelegate: NSObject, UIApplicationDelegate {

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

/// Exists only to receive `userDidAcceptCloudKitShareWith:` — it must NOT
/// create or manage a `UIWindow`; SwiftUI's `WindowGroup` continues to own
/// the window/scene lifecycle entirely.
final class PaperTrailSceneDelegate: NSObject, UIWindowSceneDelegate {

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        handleShareAcceptance(metadata: cloudKitShareMetadata, source: "scene delegate")
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
