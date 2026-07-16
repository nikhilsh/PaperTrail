import SwiftUI

// MARK: - ServiceLedgerTimelineView (docs/design-v3/V3_BRIEF.md §4, `PaperTrail
// v3 Ideas.html` C2 mock `.tl`/`.tli`/`.nd`/`.tlk`/`.tlv`/`.tls`)
//
// The Service tab's timeline spine: one node per `ServiceEntry` (mono "DATE ·
// ACTOR" kicker, bold title, "cost · job ref · photos(N)" sub-line, sage
// node), plus a trailing dashed "+ LOG A REPAIR OR SERVICE" node that opens
// `ServiceEntryFormView`. `RecordDetailView` passes entries pre-sorted via
// `ServiceEntry.sortedByDateDescending`.

struct ServiceLedgerTimelineView: View {
    let entries: [ServiceEntry]
    var onLogTapped: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // v3 animPassV3 §9 #3 "Ledger entry stamp": a newly-logged entry inks in
    // (scale 0→1, reusing the MEMBER-stamp curve at lower amplitude — a
    // modest 0.85 start rather than the paywall stamp's 2.4) and the row
    // slides under it. Off-flag this is `.identity`/`nil`, so ForEach's
    // insertion is instant exactly as in v2 — the "once" here comes for
    // free from ForEach only firing an insertion transition the moment a
    // new id actually appears, never on a re-render of existing entries.
    private var entryTransition: AnyTransition {
        guard AnimPass.isOn else { return .identity }
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.85, anchor: .top).combined(with: .opacity),
            removal: .opacity
        )
    }

    private var entryMotion: Animation? {
        guard AnimPass.isOn else { return nil }
        return AnimPass.animation(PTMotion.stampEase(AnimPass.Duration.ledgerStamp), reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                emptyRow
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    ServiceLedgerEntryRow(
                        entry: entry,
                        connectorAbove: index > 0,
                        connectorBelow: true
                    )
                    .transition(entryTransition)
                }
                .animation(entryMotion, value: entries.map(\.id))
            }
            logEntryRow
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 12))
                .foregroundStyle(PT.txt3)
                .frame(width: 10)
            Text("No service history yet")
                .font(.system(size: 12.5))
                .italic()
                .foregroundStyle(PT.txt3)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var logEntryRow: some View {
        Button(action: onLogTapped) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .foregroundStyle(PT.txt3)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
                    .frame(width: 10)
                Text("+ LOG A REPAIR OR SERVICE")
                    .font(PTFont.mono(11, medium: true))
                    .tracking(1.2)
                    .foregroundStyle(PT.gold)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

private struct ServiceLedgerEntryRow: View {
    let entry: ServiceEntry
    let connectorAbove: Bool
    let connectorBelow: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                if connectorAbove || connectorBelow {
                    Rectangle().fill(PT.hair).frame(width: 1.5)
                }
                Circle()
                    .fill(PT.inkCardDark)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(PT.sage, lineWidth: 2))
            }
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(kicker)
                    .ptMonoLabel(9, tracking: 1.6)
                    .foregroundStyle(PT.txt3)
                Text(entry.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PT.txt)
                if let sub {
                    Text(sub)
                        .font(.system(size: 11.5))
                        .foregroundStyle(PT.txt3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var kicker: String {
        let dateText = PTDate.dayMonthYear.string(from: entry.date)
        let actorLabel = entry.actorKind?.label ?? entry.actor.capitalized
        return "\(dateText) · \(actorLabel)"
    }

    /// "cost · job ref · photos(N)" — only the segments that are actually
    /// set, joined with " · " (same pattern as `CoverageLineRowView.sub`).
    private var sub: String? {
        var parts: [String] = []
        if let cost = entry.cost {
            parts.append(formattedCost(cost))
        }
        if let jobRef = entry.jobRef, !jobRef.isEmpty {
            parts.append("job \(jobRef)")
        }
        if let count = entry.attachmentIDs?.count, count > 0 {
            parts.append("photos (\(count))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formattedCost(_ cost: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "SGD"
        return formatter.string(from: NSDecimalNumber(decimal: cost)) ?? "\(cost)"
    }
}

#Preview("ServiceLedgerTimelineView") {
    ServiceLedgerTimelineView(
        entries: [
            ServiceEntry(date: .now, actor: "shop", title: "Panel flicker — mainboard replaced", cost: 0, jobRef: "SG-88231", attachmentIDs: [UUID(), UUID()]),
            ServiceEntry(date: Calendar.current.date(byAdding: .month, value: -3, to: .now)!, actor: "self", title: "Firmware 1408.4 installed")
        ],
        onLogTapped: {}
    )
    .padding(24)
    .background(PT.inkCardDark)
}
