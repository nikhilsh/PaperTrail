import UIKit
import UniformTypeIdentifiers
import os

/// Share-sheet entry point ("Share… → PaperTrail" from Photos, Files, Mail,
/// Safari, etc). Does **no** OCR/extraction here — the extension process has
/// tight memory limits and the FM/Vision pipeline can blow through them. It
/// only ferries files into the App Group container; `ShareInboxDrain` (app
/// target) picks them up on next foreground and runs the same pipeline as
/// Mail/Files "Open in PaperTrail".
///
/// No Sentry here — the extension target deliberately doesn't link it (its
/// own tight memory/process limits). Failures instead go through `os_log`,
/// visible in Console.app/sysdiagnose even without a debugger attached.
final class ShareViewController: UIViewController {

    private static let maxItems = 10

    private let iconView = UIImageView()
    private let statusLabel = UILabel()
    private var didComplete = false

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        Task { await beginImport() }
    }

    // MARK: - UI

    /// Deliberately dependency-free — no PTTheme (app-target only). The two
    /// colors are PaperTrail's ink background and gold accent, hardcoded.
    private func buildUI() {
        let ink = UIColor(red: 0x0E / 255.0, green: 0x0C / 255.0, blue: 0x09 / 255.0, alpha: 1)
        let gold = UIColor(red: 0xC2 / 255.0, green: 0xA1 / 255.0, blue: 0x5C / 255.0, alpha: 1)

        view.backgroundColor = ink

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = gold
        iconView.image = UIImage(systemName: "hourglass")
        iconView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.text = "Adding to PaperTrail…"
        statusLabel.textColor = gold
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [iconView, statusLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Import

    @MainActor
    private func beginImport() async {
        let providers = attachmentProviders()
        guard !providers.isEmpty else {
            finish(successCount: 0, totalCount: 0, containerUnavailable: false)
            return
        }

        // At most 10 small files — sequential copies keep this simple and
        // avoid handing an `NSItemProvider` across a `Sendable` boundary.
        // Each individual copy still races its own 15s timeout internally
        // (`ShareInboxWriter.copy`), so one hung provider can't stall the
        // whole loop.
        var successCount = 0
        var containerUnavailable = false
        for provider in providers {
            switch await ShareInboxWriter.copy(provider: provider) {
            case .success:
                successCount += 1
            case .containerUnavailable:
                containerUnavailable = true
            case .failure:
                break
            }
        }
        finish(successCount: successCount, totalCount: providers.count, containerUnavailable: containerUnavailable)
    }

    private func attachmentProviders() -> [NSItemProvider] {
        let inputItems = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var providers: [NSItemProvider] = []
        outer: for item in inputItems {
            for provider in item.attachments ?? [] {
                providers.append(provider)
                if providers.count >= Self.maxItems { break outer }
            }
        }
        return providers
    }

    /// `containerUnavailable` takes priority over the generic failure copy
    /// when nothing succeeded — a shared-storage problem is a distinct,
    /// more actionable failure than "this particular file didn't work".
    @MainActor
    private func finish(successCount: Int, totalCount: Int, containerUnavailable: Bool) {
        guard !didComplete else { return }
        didComplete = true

        if successCount > 0 && successCount == totalCount {
            iconView.image = UIImage(systemName: "checkmark.circle.fill")
            statusLabel.text = "Ready to import — opens in PaperTrail"
        } else if successCount > 0 {
            iconView.image = UIImage(systemName: "checkmark.circle.fill")
            statusLabel.text = "Added \(successCount) of \(totalCount) — opens in PaperTrail"
        } else if containerUnavailable {
            iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
            statusLabel.text = "Couldn't reach PaperTrail's shared storage"
        } else {
            iconView.image = UIImage(systemName: "exclamationmark.triangle.fill")
            statusLabel.text = "Couldn't import"
        }

        let delay: TimeInterval = successCount > 0 ? 0.8 : 1.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

// MARK: - Inbox writer

/// Copies a single share-sheet attachment into the App Group's `ShareInbox`
/// directory.
enum ShareInboxWriter {
    static let appGroupID = "group.nikhilsh.PaperTrail"
    static let inboxSubdirectory = "ShareInbox"

    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail.PaperTrailShare", category: "share")

    enum CopyOutcome: Equatable {
        case success
        /// The App Group container itself was unreachable (nil
        /// `containerURL`, or the inbox directory couldn't be created) —
        /// distinct from an ordinary per-item failure so the UI can show
        /// more specific copy.
        case containerUnavailable
        case failure
    }

    /// The App Group container being unreachable is a fixed condition for
    /// the whole extension run — surfaced as a thrown error so every I/O
    /// site downstream of `prepareInboxDirectory()` can tell it apart from
    /// an ordinary per-item failure without re-deriving it.
    private enum InboxError: Error {
        case containerUnavailable
    }

    /// Attempts to copy `provider`'s content into the shared inbox as a
    /// file. Raced against a 15s timeout: some third-party File Provider
    /// extensions have been seen to simply never call their completion
    /// handler, which would otherwise hang the whole share sheet. On
    /// timeout this item is counted as failed and the sequential loop in
    /// `ShareViewController.beginImport` moves on to the next provider.
    static func copy(provider: NSItemProvider) async -> CopyOutcome {
        await withTimeout(seconds: 15, operation: { await performCopy(provider: provider) }, onTimeout: { .failure })
    }

    private static func performCopy(provider: NSItemProvider) async -> CopyOutcome {
        guard let kind = preferredKind(for: provider) else { return .failure }

        let fileOutcome = await loadFileRepresentation(provider: provider, kind: kind)
        if fileOutcome != .failure {
            return fileOutcome
        }

        // Some sources (e.g. a freshly-taken screenshot handed straight from
        // Photos) only vend data, not a file URL — fall back to the raw
        // bytes and infer an extension from the provider's registered types.
        if let data = await loadDataRepresentation(provider: provider, contentType: kind.contentType) {
            let ext = fileExtension(forTypeIdentifiers: provider.registeredTypeIdentifiers, kind: kind)
            return write(data: data, extension: ext)
        }

        return .failure
    }

    // MARK: Timeout racing

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> T,
        onTimeout: @escaping @Sendable () -> T
    ) async -> T {
        await withTaskGroup(of: T.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return onTimeout()
            }
            let result = await group.next() ?? onTimeout()
            group.cancelAll()
            return result
        }
    }

    // MARK: Type inference (pure)

    enum ShareItemKind: Equatable {
        case pdf
        case image

        var contentType: UTType {
            switch self {
            case .pdf: return .pdf
            case .image: return .image
            }
        }

        var fallbackExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .image: return "jpg"
            }
        }
    }

    static func preferredKind(for provider: NSItemProvider) -> ShareItemKind? {
        if provider.hasItemConformingToTypeIdentifier(ShareItemKind.pdf.contentType.identifier) {
            return .pdf
        }
        if provider.hasItemConformingToTypeIdentifier(ShareItemKind.image.contentType.identifier) {
            return .image
        }
        return nil
    }

    /// Walks a provider's registered UTIs looking for one that actually
    /// conforms to the kind being loaded (pdf vs image) with a known
    /// filename extension; falls back to a generic extension for the item's
    /// kind if none resolve. A provider can register unrelated UTIs
    /// alongside the one that matched `preferredKind` (e.g. a generic
    /// `public.data` alongside `public.image`) — matching the *first*
    /// resolvable extension regardless of conformance previously risked
    /// naming a PDF's bytes `.png` or vice versa. Pure function of the
    /// identifier list, so it's unit-testable without an `NSItemProvider`.
    static func fileExtension(forTypeIdentifiers identifiers: [String], kind: ShareItemKind) -> String {
        for identifier in identifiers {
            if let type = UTType(identifier),
               type.conforms(to: kind.contentType),
               let ext = type.preferredFilenameExtension {
                return ext
            }
        }
        return kind.fallbackExtension
    }

    // MARK: NSItemProvider bridging

    private static func loadFileRepresentation(provider: NSItemProvider, kind: ShareItemKind) async -> CopyOutcome {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(for: kind.contentType) { url, _, error in
                guard let url, error == nil else {
                    continuation.resume(returning: .failure)
                    return
                }
                // The URL is only valid for the lifetime of this callback —
                // copy it into the App Group inbox synchronously, right
                // here, before returning. An empty `pathExtension` (seen
                // from some providers) previously produced an extensionless
                // file that later extension-sniffing would misidentify —
                // default to the kind's own extension instead.
                let ext = url.pathExtension.isEmpty ? kind.fallbackExtension : url.pathExtension
                let destination = writeInboxURL(preserving: ext)
                do {
                    try prepareInboxDirectory()
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: .success)
                } catch InboxError.containerUnavailable {
                    logger.error("ShareInboxWriter: App Group container unavailable (file copy)")
                    continuation.resume(returning: .containerUnavailable)
                } catch {
                    logger.error("ShareInboxWriter: file copy failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: .failure)
                }
            }
        }
    }

    private static func loadDataRepresentation(provider: NSItemProvider, contentType: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: contentType) { data, error in
                guard let data, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private static func write(data: Data, extension ext: String) -> CopyOutcome {
        let destination = writeInboxURL(preserving: ext)
        do {
            try prepareInboxDirectory()
            try data.write(to: destination, options: .atomic)
            return .success
        } catch InboxError.containerUnavailable {
            logger.error("ShareInboxWriter: App Group container unavailable (data write)")
            return .containerUnavailable
        } catch {
            logger.error("ShareInboxWriter: data write failed: \(error.localizedDescription, privacy: .public)")
            return .failure
        }
    }

    private static func prepareInboxDirectory() throws {
        guard let dir = inboxDirectory else {
            throw InboxError.containerUnavailable
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private static var inboxDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(inboxSubdirectory, isDirectory: true)
    }

    private static func writeInboxURL(preserving ext: String) -> URL {
        let filename = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
        // `inboxDirectory` is nil only if the App Group container is
        // unreachable, which would already have failed at
        // `prepareInboxDirectory()` — fall back to a per-call temp path so
        // callers still get a stable URL to attempt the copy/write against.
        let base = inboxDirectory ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(filename)
    }
}
