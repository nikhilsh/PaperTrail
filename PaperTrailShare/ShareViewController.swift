import UIKit
import UniformTypeIdentifiers

/// Share-sheet entry point ("Share… → PaperTrail" from Photos, Files, Mail,
/// Safari, etc). Does **no** OCR/extraction here — the extension process has
/// tight memory limits and the FM/Vision pipeline can blow through them. It
/// only ferries files into the App Group container; `ShareInboxDrain` (app
/// target) picks them up on next foreground and runs the same pipeline as
/// Mail/Files "Open in PaperTrail".
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

        statusLabel.text = "Saving to PaperTrail…"
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
            finish(successCount: 0)
            return
        }

        // At most 10 small files — sequential copies keep this simple and
        // avoid handing an `NSItemProvider` across a `Sendable` boundary.
        var successCount = 0
        for provider in providers {
            if await ShareInboxWriter.copy(provider: provider) {
                successCount += 1
            }
        }
        finish(successCount: successCount)
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

    @MainActor
    private func finish(successCount: Int) {
        guard !didComplete else { return }
        didComplete = true

        if successCount > 0 {
            iconView.image = UIImage(systemName: "checkmark.circle.fill")
            statusLabel.text = "Saved to PaperTrail"
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

    /// Attempts to copy `provider`'s content into the shared inbox as a
    /// file. Returns whether a file was written.
    static func copy(provider: NSItemProvider) async -> Bool {
        guard let kind = preferredKind(for: provider) else { return false }

        if await loadFileRepresentation(provider: provider, contentType: kind.contentType) != nil {
            return true
        }

        // Some sources (e.g. a freshly-taken screenshot handed straight from
        // Photos) only vend data, not a file URL — fall back to the raw
        // bytes and infer an extension from the provider's registered types.
        if let data = await loadDataRepresentation(provider: provider, contentType: kind.contentType) {
            let ext = fileExtension(forTypeIdentifiers: provider.registeredTypeIdentifiers, kind: kind)
            return write(data: data, extension: ext)
        }

        return false
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

    /// Walks a provider's registered UTIs looking for one with a known
    /// filename extension (png/heic/jpeg/pdf/…); falls back to a generic
    /// extension for the item's kind if none resolve. Pure function of the
    /// identifier list, so it's unit-testable without an `NSItemProvider`.
    static func fileExtension(forTypeIdentifiers identifiers: [String], kind: ShareItemKind) -> String {
        for identifier in identifiers {
            if let type = UTType(identifier), let ext = type.preferredFilenameExtension {
                return ext
            }
        }
        return kind.fallbackExtension
    }

    // MARK: NSItemProvider bridging

    private static func loadFileRepresentation(provider: NSItemProvider, contentType: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(for: contentType) { url, error in
                guard let url, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                // The URL is only valid for the lifetime of this callback —
                // copy it into the App Group inbox synchronously, right
                // here, before returning.
                let destination = writeInboxURL(preserving: url.pathExtension)
                let copied: URL?
                do {
                    try prepareInboxDirectory()
                    try FileManager.default.copyItem(at: url, to: destination)
                    copied = destination
                } catch {
                    copied = nil
                }
                continuation.resume(returning: copied)
            }
        }
    }

    private static func loadDataRepresentation(provider: NSItemProvider, contentType: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(for: contentType) { data, error in
                guard let data, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    private static func write(data: Data, extension ext: String) -> Bool {
        let destination = writeInboxURL(preserving: ext)
        do {
            try prepareInboxDirectory()
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func prepareInboxDirectory() throws {
        guard let dir = inboxDirectory else {
            throw CocoaError(.fileWriteUnknown)
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
