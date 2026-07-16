import Testing
import Foundation
@testable import PaperTrail

/// `ShareInboxDrain.shouldDrain`'s pure don't-clobber guard — no
/// SwiftData/UIKit/filesystem involved. See `AppShellView`'s equivalent
/// `pendingImportPayload == nil` guard on the Mail/Files "Open in
/// PaperTrail" path, which this mirrors plus an extra rule for not
/// interrupting an active manual capture.
///
/// `@MainActor` because `DraftPayload` lives in the app module, which
/// defaults to main-actor isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`) —
/// `shouldDrain` itself is `nonisolated` and callable from anywhere.
@MainActor
struct ShareInboxDrainTests {

    private var samplePayload: DraftPayload {
        DraftPayload(type: .receipt, attachments: [], ocr: .empty)
    }

    @Test func drainsWhenQueuedAndNothingInTheWay() {
        #expect(ShareInboxDrain.shouldDrain(hasQueuedFiles: true, pendingImportPayload: nil, showCapture: false))
    }

    @Test func doesNotDrainWhenNothingQueued() {
        #expect(!ShareInboxDrain.shouldDrain(hasQueuedFiles: false, pendingImportPayload: nil, showCapture: false))
    }

    @Test func doesNotDrainWhenAReviewCoverIsAlreadyUp() {
        #expect(!ShareInboxDrain.shouldDrain(hasQueuedFiles: true, pendingImportPayload: samplePayload, showCapture: false))
    }

    @Test func doesNotDrainDuringActiveManualCapture() {
        #expect(!ShareInboxDrain.shouldDrain(hasQueuedFiles: true, pendingImportPayload: nil, showCapture: true))
    }

    @Test func doesNotDrainWhenEverythingIsInTheWay() {
        #expect(!ShareInboxDrain.shouldDrain(hasQueuedFiles: true, pendingImportPayload: samplePayload, showCapture: true))
    }
}
