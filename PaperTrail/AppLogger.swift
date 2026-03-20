import Foundation
import OSLog
import Sentry

enum AppLogger {
    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "app")

    static var isSentryEnabled: Bool {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String else {
            return false
        }
        return !dsn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func info(_ message: String, category: String = "app") {
        logger.log(level: .info, "[\(category)] \(message, privacy: .public)")
    }

    static func warn(_ message: String, category: String = "app") {
        logger.warning("[\(category)] \(message, privacy: .public)")
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
}
