import Foundation
import UIKit
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
    private static let failedSubdirectory = "failed"

    private static var inboxURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(inboxSubdirectory, isDirectory: true)
    }

    /// Where quarantined originals go instead of being deleted — a share
    /// that fails to copy or yields no usable images is kept here rather
    /// than lost outright, and (just as important) never sits in the main
    /// inbox where it would keep getting picked up and re-failed on every
    /// future foreground.
    private static var failedURL: URL? {
        inboxURL?.appendingPathComponent(failedSubdirectory, isDirectory: true)
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
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: inboxURL, includingPropertiesForKeys: nil)) ?? []
        // The `failed` quarantine subdirectory lives inside the inbox
        // itself — never treat it (or anything under it) as a file to
        // drain, or a poison file would wedge every future drain right
        // back open the moment it's quarantined.
        let fileURLs = entries.filter { $0.lastPathComponent != failedSubdirectory }
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
        let router = AppRouter.shared
        // Checked and set synchronously, before any `await` in this
        // function, so a concurrently-running `importIncomingFile` (Mail/
        // Files "Open in PaperTrail") can't slip past this guard and race
        // to assign `pendingImportPayload` too.
        guard !router.isImporting else {
            AppLogger.info("Share drain deferred — an import is already in flight", category: "import")
            return
        }
        router.isImporting = true
        defer { router.isImporting = false }

        AppLogger.info("Draining \(fileURLs.count) shared file(s)", category: "import")

        // Copy failures and files that yield no images are quarantined,
        // not deleted — tracked separately per original so a bad file in a
        // multi-file share doesn't take down the good ones with it.
        var copies: [(original: URL, local: URL)] = []
        var quarantined: [URL] = []
        for url in fileURLs {
            if let copy = DocumentInbox.copy(url) {
                copies.append((original: url, local: copy))
            } else {
                quarantined.append(url)
            }
        }
        defer { for copy in copies { DocumentInbox.delete(copy.local) } }

        var images: [UIImage] = []
        var succeeded: [URL] = []
        for copy in copies {
            let pageImages = ImportPipeline.images(fromFileURL: copy.local)
            if pageImages.isEmpty {
                quarantined.append(copy.original)
            } else {
                images.append(contentsOf: pageImages)
                succeeded.append(copy.original)
            }
        }

        quarantine(quarantined)

        guard !images.isEmpty else {
            AppLogger.error("Shared file drain: no images extracted from any file", category: "import")
            return
        }

        let learned = MerchantLearningService(modelContext: modelContext).learnedMerchantNames()
        let result = await ScanningService().process(images: images, type: .receipt, learnedMerchants: learned)

        // Re-check every don't-clobber guard right before committing — the
        // review cover or manual capture may have opened while extraction
        // was running (it awaits OCR/FM, which can take a few seconds). If
        // blocked now, leave the successful originals in the inbox
        // untouched; they drain again next foreground. Only the temp
        // copies (cleaned up above) are ours to discard either way.
        guard shouldDrain(
            hasQueuedFiles: true,
            pendingImportPayload: router.pendingImportPayload,
            showCapture: router.showCapture
        ) else {
            AppLogger.warn("Share drain result discarded — import state changed mid-drain", category: "import")
            return
        }

        // Only now, with the payload about to land, remove the originals
        // that actually contributed to it.
        for url in succeeded {
            try? FileManager.default.removeItem(at: url)
        }

        router.pendingImportPayload = DraftPayload(type: .receipt, attachments: result.attachments, ocr: result.ocr)
        AppLogger.info("Shared file(s) routed to review", category: "import")
    }

    /// Moves quarantined originals into `ShareInbox/failed/` instead of
    /// deleting them, so a bad share isn't silently lost — and the drain
    /// loop doesn't retry (and re-fail) the same file on every future
    /// foreground. Counts only in the log — never filenames or paths,
    /// which can carry PII from the shared document's original name.
    private static func quarantine(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let failedURL else { return }
        try? FileManager.default.createDirectory(at: failedURL, withIntermediateDirectories: true)
        for url in urls {
            let destination = failedURL.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: destination) // clear any stale same-name file first
            do {
                try FileManager.default.moveItem(at: url, to: destination)
            } catch {
                // Best-effort — if even the move fails, delete so it
                // doesn't wedge future drains.
                try? FileManager.default.removeItem(at: url)
            }
        }
        AppLogger.warn("Quarantined \(urls.count) shared file(s) that failed import", category: "import")
    }
}
