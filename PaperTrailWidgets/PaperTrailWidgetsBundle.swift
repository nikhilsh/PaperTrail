import WidgetKit
import SwiftUI

@main
struct PaperTrailWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ExpiringSoonWidget()
        // v3 shelfWidgets (docs/design-v3/V3_BRIEF.md §1) — WidgetBundle
        // composition is static, so these three always appear in the
        // gallery; each renders a flag-off fallback state until
        // `shelfWidgets` is turned on (see ShelfWidgets.swift header).
        ClosingSoonWidget()
        CoverageRingWidget()
        NextUpWidget()
    }
}
