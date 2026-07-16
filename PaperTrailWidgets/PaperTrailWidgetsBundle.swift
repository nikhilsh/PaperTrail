import WidgetKit
import SwiftUI

@main
struct PaperTrailWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ExpiringSoonWidget()
        // v3 shelfWidgets (docs/design-v3/V3_BRIEF.md §1) — compiled out of
        // APPSTORE builds entirely (item 4, HIGH: APPSTORE surface leaks).
        // Previously these always shipped to the widget gallery, flag or no
        // flag, on the theory that a flag-off fallback state was harmless —
        // but "the v3 widget kind exists at all" is itself a v3 surface an
        // App Store build must be provably free of, same as the app target's
        // own `#if !APPSTORE` gates.
        #if !APPSTORE
        ClosingSoonWidget()
        CoverageRingWidget()
        NextUpWidget()
        #endif
    }
}
