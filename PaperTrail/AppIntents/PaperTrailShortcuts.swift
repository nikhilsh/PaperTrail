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
        AppShortcut(
            intent: CheckWarrantyIntent(),
            phrases: [
                "Is my \(.applicationName) item under warranty",
                "Check warranty in \(.applicationName)"
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
        // v3 §8 (siriIntents): registered UNCONDITIONALLY — a runtime
        // `if FeatureFlags.isOn(.siriIntents)` here does not compile:
        // `@AppShortcutsBuilder`'s `buildOptional` is marked unavailable
        // ("if statements in an AppShortcutsBuilder can only be used with
        // #available clauses"), because the phrase list is extracted
        // statically at build time. That's fine for the flag contract:
        // the phrase existing is not a v3 surface, and AddItemIntent's
        // `perform` just opens capture — same as tapping the app's own add
        // button — so reaching it with the flag off is harmless. The flag
        // gates the actual new surface (the v3 snippet card).
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
