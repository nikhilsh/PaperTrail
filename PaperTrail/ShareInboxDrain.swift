import Foundation
import SwiftData

/// Drains files the `PaperTrailShare` extension dropped into the App
/// Group's `ShareInbox` directory. The extension does no OCR/extraction
/// (memory limits), so it just copies files there and completes — this is
/// where they actually get run through the same pipeline as Mail/Files
/// "Open in PaperTrail" (`AppShellView.importIncomingFile`).
///
/// Called from `AppShellView`'s scene-active hook, the same place
/// `SpotlightIndexer`/`DigestScheduler` refresh.
@MainActor
enum ShareInboxDrain {
    private static let appGroupID = "group.nikhilsh.PaperTrail"
    private static let inboxSubdirectory = "ShareInbox"

    private static var inboxURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(inboxSubdirectory, isDirectory: true)
    }

    /// Mirrors `AppShellView`'s don't-clobber rule for `pendingImportPayload`
    /// (a review cover already up), plus a drain-specific rule: don't yank
    /// the user out of an active manual capture. Pure and `nonisolated` (it
    /// touches no actor-isolated state) so it's testable directly, without
    /// SwiftData/UIKit/the filesystem or hopping to the main actor.
    nonisolated static func shouldDrain(hasQueuedFiles: Bool, pendingImportPayload: DraftPayload?, showCapture: Bool) -> Bool {
        hasQueuedFiles && pendingImportPayload == nil && !showCapture
    }

    /// No-ops if there's nothing queued, or if the guard blocks — in the
    /// latter case the files are left in place for the next foreground
    /// (that's the queue).
    static func drainIfPossible(modelContext: ModelContext) {
        guard let inboxURL else { return }
        let fileURLs = (try? FileManager.default.contentsOfDirectory(
            at: inboxURL, includingPropertiesForKeys: nil)) ?? []
        guard !fileURLs.isEmpty else { return }

        let router = AppRouter.shared
        guard shouldDrain(
            hasQueuedFiles: true,
            pendingImportPayload: router.pendingImportPayload,
            showCapture: router.showCapture
        ) else { return }

        Task { await drain(fileURLs: fileURLs, modelContext: modelContext) }
    }

    private static func drain(fileURLs: [URL], modelContext: ModelContext) async {
        AppLogger.info("Draining \(fileURLs.count) shared file(s)", category: "import")

        var localCopies: [URL] = []
        for url in fileURLs {
            if let copy = DocumentInbox.copy(url) {
                localCopies.append(copy)
            }
        }
        // Remove the originals from the App Group inbox regardless of
        // per-file copy success — a bad file shouldn't leave a poison entry
        // that blocks every future foreground drain.
        for url in fileURLs {
            try? FileManager.default.removeItem(at: url)
        }

        guard !localCopies.isEmpty else {
            AppLogger.error("Shared file drain: no files copied from inbox", category: "import")
            return
        }
        defer { for copy in localCopies { DocumentInbox.delete(copy) } }

        let images = ImportPipeline.images(fromFileURLs: localCopies)
        guard !images.isEmpty else {
            AppLogger.error("Shared file drain: no images extracted", category: "import")
            return
        }

        let learned = MerchantLearningService(modelContext: modelContext).learnedMerchantNames()
        let result = await ScanningService().process(images: images, type: .receipt, learnedMerchants: learned)

        AppRouter.shared.pendingImportPayload = DraftPayload(type: .receipt, attachments: result.attachments, ocr: result.ocr)
        AppLogger.info("Shared file(s) routed to review", category: "import")
    }
}
