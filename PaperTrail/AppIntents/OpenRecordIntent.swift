//
//  OpenRecordIntent.swift
//  PaperTrail
//
//  "Open <item> in PaperTrail." READ-ONLY: just foregrounds the app.
//
//  The app has no deep-link mechanism to jump straight to a record today —
//  there's no `onOpenURL` handler and no shared `NavigationPath`/route enum;
//  `AppShellView.AppRouter` (AppShellView.swift) only tracks which tab is
//  selected and whether the capture sheet is up, nothing record-specific.
//  Building that plumbing is out of scope for this read-only App Intents
//  pass, so this intent opens the app plainly and stops there. See the PR
//  description for the follow-up if deep-linking to a specific record is
//  wanted later.
//

import AppIntents

struct OpenRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Item in PaperTrail"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Item")
    var record: RecordEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$record) in PaperTrail")
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
