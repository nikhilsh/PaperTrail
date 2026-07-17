import WidgetKit
import SwiftUI

@main
struct PaperTrailWidgetsBundle: WidgetBundle {
    // Bundle composition is a compile-time split (BUILD_REVIEW W4/W5):
    //
    // - APPSTORE: the v2 `ExpiringSoonWidget` only, verbatim — the shipped
    //   App Store surface is pixel-frozen (hard constraint), and the v3
    //   shelf kinds must not exist in that binary at all.
    // - Dev/OTA: the corrected shelf set ONLY — small ×2 (coverage ring +
    //   "Next up"), medium ("Closing soon"), and the Lock Screen families
    //   ("Next up" inline + "Quick Shelve" circular). The legacy
    //   `ExpiringSoonWidget` is dropped from these galleries on purpose:
    //   its systemSmall was the dishonest "321d" 40pt countdown (W4 — a
    //   false siren for a non-urgent item; the coverage ring owns that
    //   slot now) and its systemMedium duplicated the paper medium with
    //   less info per row (W5).
    var body: some Widget {
        #if APPSTORE
        ExpiringSoonWidget()
        #else
        CoverageRingWidget()
        NextUpWidget()
        ClosingSoonWidget()
        QuickShelveWidget()
        #endif
    }
}
