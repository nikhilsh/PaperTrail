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
        // v3 §8 (siriIntents): `@AppShortcutsBuilder` is a result builder, same
        // as `@ViewBuilder`, so it does support a runtime `if` here — this
        // isn't a compile-time `#if`. What's genuinely uncertain (undocumented,
        // and this repo has no Mac to check locally — CI-compile-only) is
        // whether Xcode's App Intents metadata-extraction build step, which
        // statically walks this property to precompute the Shortcuts/Siri
        // phrase list, resolves a runtime condition the same way at build
        // time as `appShortcuts` resolves it when the OS actually calls this
        // getter. If that extraction step ever silently drops or duplicates
        // the phrase instead of tracking the flag, the fallback per the v3
        // brief is to register it unconditionally — AddItemIntent's `perform`
        // is harmless to reach with the flag off, it only opens capture.
        if FeatureFlags.isOn(.siriIntents) {
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
}

// Note: OpenRecordIntent has no AppShortcut phrase — it needs a specific item
// bound to read naturally as a Siri phrase, which isn't knowable ahead of
// time. It's still available for Shortcuts automations (Shortcuts app
// discovers every AppIntent in the app automatically); this provider only
// registers the phrases Siri understands "out of the box".
