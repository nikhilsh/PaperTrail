//
//  PaperTrailShortcuts.swift
//  PaperTrail
//
//  Registers the natural-language phrases Siri/Shortcuts uses to find these
//  intents. No Info.plist entries needed — the App Intents framework
//  discovers `AppShortcutsProvider` conformances automatically.
//

import AppIntents

struct PaperTrailShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        // Parameterized phrases let Siri match a SPECIFIC item by name
        // ("check my Samsung TV warranty in PaperTrail") instead of always
        // asking "which item?" afterwards. The item vocabulary comes from
        // RecordEntity.suggestedEntities and is refreshed via
        // `PaperTrailShortcuts.updateAppShortcutParameters()` after saves.
        //
        // Platform limit worth knowing: EVERY route into a third-party app
        // still requires the app's name somewhere in the utterance. "What's
        // my Samsung TV warranty" with no "PaperTrail" goes to Siri's own
        // knowledge, and no phrase list here can intercept it — that only
        // changes if Apple opens an assistant-schema domain for this.
        AppShortcut(
            intent: CheckWarrantyIntent(),
            phrases: [
                "Is my \(.applicationName) item under warranty",
                "Check warranty in \(.applicationName)",
                "Check my warranty in \(.applicationName)",
                "Check my \(\.$record) warranty in \(.applicationName)",
                "Check warranty on \(\.$record) in \(.applicationName)",
                "Is my \(\.$record) under warranty in \(.applicationName)",
                "When does my \(\.$record) warranty expire in \(.applicationName)"
            ],
            shortTitle: "Check Warranty",
            systemImageName: "checkmark.seal"
        )
        AppShortcut(
            intent: ExpiringSoonIntent(),
            phrases: [
                "What's expiring soon in \(.applicationName)"
            ],
            shortTitle: "Expiring Soon",
            systemImageName: "clock.badge.exclamationmark"
        )
        // v3 §8 (siriIntents): registered UNCONDITIONALLY with respect to
        // the *runtime* flag — a runtime `if FeatureFlags.isOn(.siriIntents)`
        // here does not compile: `@AppShortcutsBuilder`'s `buildOptional` is
        // marked unavailable, because the phrase list is extracted
        // statically at build time. Ships in App Store builds too since the
        // v1.1 store pass turned the flags on there.
        AppShortcut(
            intent: AddItemIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Add an item in \(.applicationName)"
            ],
            shortTitle: "Add Item",
            systemImageName: "plus.rectangle.on.folder"
        )
    }
}

// Note: OpenRecordIntent has no AppShortcut phrase — it needs a specific item
// bound to read naturally as a Siri phrase, which isn't knowable ahead of
// time. It's still available for Shortcuts automations (Shortcuts app
// discovers every AppIntent in the app automatically); this provider only
// registers the phrases Siri understands "out of the box".
