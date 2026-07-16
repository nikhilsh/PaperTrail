//
//  AddItemIntent.swift
//  PaperTrail
//
//  "Add to PaperTrail" — v3 §8 (siriIntents). Opens straight to capture;
//  it never writes anything itself, matching the read-only-except-navigation
//  contract every other intent in this folder follows. Registered like
//  `OpenRecordIntent`: always compiled/discoverable by the Shortcuts app,
//  but its Siri phrase in `PaperTrailShortcuts` only appears when the
//  `siriIntents` flag is on (see that file for why the intent itself can't
//  be conditionally compiled on a runtime flag).
//

import AppIntents

struct AddItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to PaperTrail"
    static var description = IntentDescription(
        "Start scanning a new purchase into PaperTrail."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Routes to capture; if `addSheetV2` is also on, AppRouter's capture
        // presentation shows the new sheet — that sheet's contents are owned
        // elsewhere, this intent only ever asks for ".capture".
        AppRouter.shared.navigate(to: .capture)
        return .result()
    }
}
