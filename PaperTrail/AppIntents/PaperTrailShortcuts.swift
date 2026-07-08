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
    }
}

// Note: OpenRecordIntent has no AppShortcut phrase — it needs a specific item
// bound to read naturally as a Siri phrase, which isn't knowable ahead of
// time. It's still available for Shortcuts automations (Shortcuts app
// discovers every AppIntent in the app automatically); this provider only
// registers the phrases Siri understands "out of the box".
