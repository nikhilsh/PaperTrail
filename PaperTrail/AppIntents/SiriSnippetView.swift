//
//  SiriSnippetView.swift
//  PaperTrail
//
//  The `siriIntents`-flagged (V3 §8) Siri snippet card for CheckWarrantyIntent
//  — a compact paper passport per the V3-4 mock
//  (docs/design-v3/"PaperTrail v3 Screens.html"): kicker, Covered/Expired
//  stamp, serif item name, plain-language answer, sage progress bar, and two
//  actions.
//
//  CheckWarrantyIntent's own `AppIntents`/SwiftData imports confirm this
//  intent has no dedicated App Intents Extension target — it runs inside the
//  main `PaperTrail` app target (foregrounded or backgrounded by the system
//  to service Siri), so `PT`/`PTComponents` are linked in and safe to reuse
//  directly. No hardcoded widget-style mini-palette needed here.
//
//  Flag OFF: CheckWarrantyIntent still returns the pre-v3 `WarrantySnippetView`
//  (see CheckWarrantyIntent.swift) — this file is additive, not a replacement.
//

import AppIntents
import SwiftUI

/// The paper snippet card shown for a resolved record. Read-only presentation
/// — the two actions below hand off to `OpenRecordIntent`, never mutate.
struct SiriSnippetCardView: View {
    let entity: RecordEntity
    let warrantyStatus: WarrantyStatus
    let answer: String
    let progressElapsed: Double

    /// Whether this record has proof attached, i.e. whether "Build claim
    /// packet" would actually offer anything back in the app —
    /// `ClaimPacketAvailability.isOffered(attachmentCount:)` (ClaimPacketView.swift).
    /// BUILD CLAIM is hidden rather than shown as a dead end when this is false.
    let hasClaimablePacket: Bool

    private var stampText: String {
        switch warrantyStatus {
        case .active, .expiringSoon: "Covered"
        case .expired: "Expired"
        case .unknown: "No Warranty"
        }
    }

    private var tone: Color {
        switch warrantyStatus {
        case .active: PT.sage
        case .expiringSoon: PT.amber
        case .expired: PT.terra
        case .unknown: PT.txt3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Papertrail")
                    .ptMonoLabel(10, tracking: 2)
                    .foregroundStyle(PT.goldDeep)
                Spacer()
                StampBadge(text: stampText, tone: tone, compact: true)
            }

            Text(entity.productName)
                .font(PTFont.serif(22, weight: 600))
                .foregroundStyle(PT.onPaper)

            Text(answer)
                .font(.system(size: 13))
                .foregroundStyle(PT.onPaper2)

            WarrantyProgressBar(progress: progressElapsed, tone: tone, onPaper: true, height: 4)
                .padding(.top, 2)

            HStack {
                // OPEN PASSPORT — always available: routes to the record via
                // OpenRecordIntent (openAppWhenRun), same deep link
                // `papertrail://record/<uuid>` a Spotlight hit or widget tap uses.
                Button(intent: OpenRecordIntent.opening(entity)) {
                    Text("Open Passport ›")
                        .ptMonoLabel(9.5, tracking: 1.4)
                        .foregroundStyle(PT.goldDeep)
                }
                .buttonStyle(.plain)

                Spacer()

                // BUILD CLAIM — no standalone claim-packet deep link exists
                // (ClaimPacketView is only reachable via NavigationLink pushed
                // from RecordDetailView, no `papertrail://` route or AppRouter
                // case for it — see AppShellView.swift `Route`). Rather than
                // invent one, this also opens the passport, where "Build claim
                // packet" is one tap away; only shown when the record actually
                // has proof to build a claim from.
                if hasClaimablePacket {
                    Button(intent: OpenRecordIntent.opening(entity)) {
                        Text("Build Claim")
                            .ptMonoLabel(9.5, tracking: 1.4)
                            .foregroundStyle(PT.onPaper3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
        .padding(18)
        .paperCard()
    }
}

/// Shown instead of `SiriSnippetCardView` when the device is locked /
/// protected data is unavailable — no record content leaks onto the Siri
/// snippet surface while the phone is locked (V3_BRIEF.md §8).
struct LockedSnippetCardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Papertrail")
                .ptMonoLabel(10, tracking: 2)
                .foregroundStyle(PT.goldDeep)
            Text("Unlock PaperTrail to see this.")
                .font(.system(size: 14))
                .foregroundStyle(PT.onPaper2)
        }
        .padding(18)
        .paperCard()
    }
}

private extension OpenRecordIntent {
    /// Builds a ready-to-run `OpenRecordIntent` bound to `entity` —
    /// `@Parameter`-backed intents are plain mutable structs, so this is just
    /// property assignment, not some special constructor.
    static func opening(_ entity: RecordEntity) -> OpenRecordIntent {
        var intent = OpenRecordIntent()
        intent.record = entity
        return intent
    }
}
