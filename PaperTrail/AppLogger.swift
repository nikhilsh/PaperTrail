import Foundation
import OSLog
import Sentry

enum AppLogger {
    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "app")

    static var sentryHost: String? {
        guard let url = URL(string: BuildSecrets.sentryDSN) else {
            return nil
        }
        return url.host
    }

    static var isSentryEnabled: Bool {
        !BuildSecrets.sentryDSN.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // info/warn used to be OSLog-only, which made every non-crashing sync
    // problem undiagnosable off-device (the household member-sync gap shipped
    // dark this way). They now also leave a Sentry breadcrumb — so any later
    // error event carries the flow that led to it — and forward to Sentry
    // structured logs (queryable without an error ever firing).
    static func info(_ message: String, category: String = "app") {
        logger.log(level: .info, "[\(category)] \(message, privacy: .public)")
        guard isSentryEnabled else { return }
        breadcrumb(level: .info, category: category, message: message)
        SentrySDK.logger.info("[\(category)] \(message)")
    }

    static func warn(_ message: String, category: String = "app") {
        logger.warning("[\(category)] \(message, privacy: .public)")
        guard isSentryEnabled else { return }
        breadcrumb(level: .warning, category: category, message: message)
        SentrySDK.logger.warn("[\(category)] \(message)")
    }

    private static func breadcrumb(level: SentryLevel, category: String, message: String) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    static func error(_ message: String, category: String = "app", sendToSentry: Bool = true, tags: [String: String] = [:]) {
        logger.error("[\(category)] \(message, privacy: .public)")

        guard sendToSentry, isSentryEnabled else { return }

        SentrySDK.configureScope { scope in
            for (key, value) in tags {
                scope.setTag(value: value, key: key)
            }
            scope.setLevel(.error)
        }
        SentrySDK.capture(message: "[\(category)] \(message)")
    }

    static func testEvent() {
        info("Manual Sentry test event requested", category: "observability")
        error("Manual test event from Settings", category: "observability", tags: ["kind": "manual_test"])
    }
}
