//
//  OpenRecordIntent.swift
//  PaperTrail
//
//  "Open <item> in PaperTrail." READ-ONLY: routes to the specific record via
//  `AppRouter.shared` (AppShellView.swift) and foregrounds the app.
//  `AppRouter` is a singleton specifically so an App Intent — which may run
//  in a process the OS launched just to service it, before `AppShellView`
//  exists — can set the pending route immediately; the shell picks it up as
//  soon as it appears.
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

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.navigate(to: .record(record.id))
        return .result()
    }
}
