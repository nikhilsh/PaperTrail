import WidgetKit
import SwiftUI

// MARK: - v3 shelfWidgets (Ideas C1)
//
// Three new widget kinds behind `FeatureFlags.isOn(.shelfWidgets)`
// (`docs/design-v3/V3_BRIEF.md` §1): a medium paper "Closing soon" card, a
// small paper coverage ring, and a small dark "Next up" card (which also
// supplies the `.accessoryInline` Lock Screen family). All three reuse
// `ExpiringSoonProvider`/`ExpiringSoonEntry` from `ExpiringSoonWidget.swift`
// — one snapshot-loading path for every widget kind in the extension — and
// are added to the `WidgetBundle` in `PaperTrailWidgetsBundle.swift`.
//
// The `WidgetBundle` composition is static: within a non-APPSTORE build
// these three kinds always appear in the widget gallery, flag or no flag
// (WidgetKit has no runtime way to hide a bundle member). When the flag is
// off, every view here renders "Enable in Settings → Flags" rather than the
// v2 widget's genuine no-data fallback ("Open PaperTrail to update") — the
// two states need distinct copy so a user can tell "feature disabled" from
// "broken".
//
// **APPSTORE builds compile these three kinds out of the bundle entirely**
// (`PaperTrailWidgetsBundle`'s `#if !APPSTORE`, item 4 HIGH) — "the widget
// kind ships to the gallery ahead of the feature being turned on" was a
// deliberate tradeoff for TestFlight/DEBUG builds, but wasn't an acceptable
// one for App Store: the v3 widget kind existing at all is itself a surface
// an App Store binary must be provably free of.

private let shelfPaperBackground = LinearGradient(
    colors: [WidgetPalette.paperTop, WidgetPalette.paperBottom],
    startPoint: .top,
    endPoint: .bottom
)

// MARK: - Shared day/date phrasing

/// Formatting specific to the shelf widgets' paper-mock copy (spelled-out
/// day counts, "d MMM" dates) — distinct from `ExpiringSoonFormatting`'s
/// compact "6d" Lock Screen/v2 style, which the shelf widgets also reuse
/// directly for `daysLeft`/`deepLink`/`kindLabel`.
enum ShelfFormatting {
    /// "22 Jul" — fixed locale so the string is deterministic across
    /// devices/regions, same rationale as `DigestSummary.totalsText`.
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    /// "today", "1 day", "6 days", "expired" — the spelled-out form the C1
    /// mock uses for the urgency pill and "Next up" headline.
    static func dayPhrase(_ daysLeft: Int) -> String {
        if daysLeft < 0 { return "expired" }
        if daysLeft == 0 { return "today" }
        if daysLeft == 1 { return "1 day" }
        return "\(daysLeft) days"
    }

    /// Two-line serif headline for the "Next up" widget, keyed by event
    /// kind — e.g. "Return window\ncloses in 6 days" (the C1 mock's exact
    /// copy for a return event) or "Warranty\nends in 6 days".
    static func headline(kind: String, daysLeft: Int) -> String {
        let phrase = dayPhrase(daysLeft)
        let verb = daysLeft <= 0 ? phrase : "in \(phrase)"
        switch kind {
        case "return":
            return "Return window\ncloses \(verb)"
        default:
            return "Warranty\nends \(verb)"
        }
    }
}

// MARK: - Paper empty state

/// The cream/paper counterpart to `EmptyStateView` — used by the "Closing
/// soon" and coverage-ring widgets, which render on the paper background
/// rather than the dark one.
private struct PaperEmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 4) {
            Text("PaperTrail")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WidgetPalette.goldDeep)
            Text(message)
                .font(.footnote)
                .foregroundStyle(WidgetPalette.ink)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(shelfPaperBackground, for: .widget)
    }
}

/// A short horizontal dashed rule — the divider between the two urgency
/// rows on the "Closing soon" card, matching the mock's
/// `border-top:1px dashed`.
private struct DashedRule: View {
    var body: some View {
        DashedLine()
            .stroke(WidgetPalette.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    private struct DashedLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

// MARK: - "Closing soon" (medium, paper)

/// The amber "N days"/"today"/"expired" pill next to the return-window row.
private struct UrgencyPill: View {
    let daysLeft: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(WidgetPalette.amber).frame(width: 5, height: 5)
            Text(ShelfFormatting.dayPhrase(daysLeft))
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
        }
        .foregroundStyle(WidgetPalette.amber)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(WidgetPalette.amber.opacity(0.14), in: Capsule())
    }
}

/// One "closing soon" row — a return window or a warranty deadline, sharing
/// one visual treatment (name + kind-specific subtitle + day-count pill) so
/// up to three can sit together at the same density as the dark
/// ExpiringSoon medium widget's `MediumWidgetRow`, without singling out
/// returns the way the old return-only row did.
private struct ClosingSoonItemRow: View {
    let item: WidgetSnapshotItem
    let asOf: Date

    private var subtitle: String {
        item.kind == "return"
            ? "Last day to change your mind: \(ShelfFormatting.shortDate(item.date))"
            : "Warranty ends \(ShelfFormatting.shortDate(item.date))"
    }

    var body: some View {
        let daysLeft = ExpiringSoonFormatting.daysLeft(from: asOf, to: item.date)
        let row = HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
                    .privacySensitive()
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.inkSecondary)
                    .lineLimit(1)
                    .privacySensitive()
            }
            Spacer(minLength: 8)
            UrgencyPill(daysLeft: daysLeft)
        }
        if let destination = ExpiringSoonFormatting.deepLink(for: item) {
            Link(destination: destination) { row }
        } else {
            row
        }
    }
}

/// The register-it nudge, given the same two-line title-plus-subtitle
/// treatment as `ClosingSoonItemRow` so it never reads as a single thin
/// line floating alone in the card. The subtitle stays generic — the
/// snapshot doesn't carry the record's warranty term, so this doesn't
/// invent a specific duration.
private struct RegisterNudgeRow: View {
    let nudge: WidgetRegisterNudge

    var body: some View {
        let row = HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(nudge.name) — register it")
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
                    .privacySensitive()
                Text("Register to unlock full coverage")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("REGISTER →")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(WidgetPalette.goldDeep)
        }
        if let destination = URL(string: "papertrail://record/\(nudge.recordID.uuidString)") {
            Link(destination: destination) { row }
        } else {
            row
        }
    }
}

/// Up to three closing-soon rows, nearest deadline first (mixed return and
/// warranty events, already sorted by `WidgetSnapshotWriter.nearestUpcoming`),
/// plus the register nudge as a bonus row when there's room left under the
/// three-row cap — the nudge never bumps a genuine deadline out.
private struct ClosingSoonRows {
    let items: [WidgetSnapshotItem]
    let registerNudge: WidgetRegisterNudge?

    /// systemMedium fits the header plus TWO ~30pt rows and one divider —
    /// three rows overflowed the canvas and clipped the bottom row on
    /// device (build 39). The nudge only rides along when it fits in the
    /// two-row budget, i.e. when there's at most one real item.
    init(entry: ExpiringSoonEntry) {
        let capped = Array(entry.items.prefix(2))
        items = capped
        registerNudge = capped.count < 2 ? entry.registerNudge : nil
    }

    var isEmpty: Bool { items.isEmpty && registerNudge == nil }
}

private struct ClosingSoonWidgetView: View {
    let entry: ExpiringSoonEntry

    var body: some View {
        if !FeatureFlags.isOn(.shelfWidgets) {
            PaperEmptyStateView(message: "Enable in Settings → Flags")
        } else {
            let rows = ClosingSoonRows(entry: entry)
            if rows.isEmpty {
                PaperEmptyStateView(message: entry.emptyStateMessage)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PAPERTRAIL · CLOSING SOON")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(WidgetPalette.goldDeep)
                        .padding(.bottom, 12)

                    ForEach(Array(rows.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { DashedRule() }
                        ClosingSoonItemRow(item: item, asOf: entry.date)
                    }
                    if let nudge = rows.registerNudge {
                        if !rows.items.isEmpty { DashedRule() }
                        RegisterNudgeRow(nudge: nudge)
                    }
                }
                // No manual .padding() — WidgetKit already applies content
                // margins around containerBackground content; doubling them
                // cost ~30pt of the canvas and contributed to the clipping.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .containerBackground(shelfPaperBackground, for: .widget)
            }
        }
    }
}

struct ClosingSoonWidget: Widget {
    let kind: String = "ClosingSoonWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExpiringSoonProvider()) { entry in
            ClosingSoonWidgetView(entry: entry)
        }
        .configurationDisplayName("Closing Soon")
        .description("Warranties, return windows, and register-it nudges that need attention.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Coverage ring (small, paper)

private struct CoverageRingWidgetView: View {
    let entry: ExpiringSoonEntry

    var body: some View {
        if !FeatureFlags.isOn(.shelfWidgets) {
            PaperEmptyStateView(message: "Enable in Settings → Flags")
        } else if let total = entry.totalCount, total > 0, let covered = entry.coveredCount {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(WidgetPalette.ringTrack, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    Circle()
                        .trim(from: 0, to: CGFloat(covered) / CGFloat(total))
                        .stroke(WidgetPalette.sage, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(covered)/\(total)")
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetPalette.ink)
                        .minimumScaleFactor(0.7)
                        .privacySensitive()
                }
                .frame(width: 92, height: 92)

                Text(captionText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(WidgetPalette.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .privacySensitive()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(shelfPaperBackground, for: .widget)
            .widgetURL(URL(string: "papertrail://expiring"))
        } else {
            PaperEmptyStateView(message: entry.emptyStateMessage)
        }
    }

    /// Prefers the compact total ("S$3.1k") so it never truncates in a
    /// small widget's caption line; falls back to the long form
    /// (`totalValueText`, e.g. "SGD 3,116") for a snapshot written by an
    /// app build that predates the compact field.
    private var captionText: String {
        guard let valueText = entry.totalValueCompactText ?? entry.totalValueText else { return "covered" }
        return "covered · \(valueText)"
    }
}

struct CoverageRingWidget: Widget {
    let kind: String = "CoverageRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExpiringSoonProvider()) { entry in
            CoverageRingWidgetView(entry: entry)
        }
        .configurationDisplayName("Coverage Ring")
        .description("How much of your library is still under warranty.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Next up (small dark + accessoryInline)

private struct NextUpSmallView: View {
    let entry: ExpiringSoonEntry

    var body: some View {
        if let item = entry.items.first {
            let daysLeft = ExpiringSoonFormatting.daysLeft(from: entry.date, to: item.date)
            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT UP")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(WidgetPalette.gold)

                Text(ShelfFormatting.headline(kind: item.kind, daysLeft: daysLeft))
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(WidgetPalette.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                Text("\(item.name.uppercased()) · \(ShelfFormatting.shortDate(item.date).uppercased())")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(WidgetPalette.cream.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .privacySensitive()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(WidgetPalette.background, for: .widget)
            .widgetURL(ExpiringSoonFormatting.deepLink(for: item))
        } else {
            EmptyStateView(message: entry.emptyStateMessage)
        }
    }
}

private struct NextUpAccessoryInlineView: View {
    let entry: ExpiringSoonEntry

    var body: some View {
        if let item = entry.items.first {
            let daysLeft = ExpiringSoonFormatting.daysLeft(from: entry.date, to: item.date)
            Text("\(item.name) · \(ExpiringSoonFormatting.bigLabel(daysLeft))")
                .privacySensitive()
        } else {
            Text(entry.emptyStateMessage)
        }
    }
}

private struct NextUpWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ExpiringSoonEntry

    var body: some View {
        if !FeatureFlags.isOn(.shelfWidgets) {
            switch family {
            case .accessoryInline:
                Text("Enable in Settings → Flags")
            default:
                EmptyStateView(message: "Enable in Settings → Flags")
            }
        } else {
            switch family {
            case .accessoryInline:
                NextUpAccessoryInlineView(entry: entry)
            default:
                NextUpSmallView(entry: entry)
            }
        }
    }
}

struct NextUpWidget: Widget {
    let kind: String = "NextUpWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExpiringSoonProvider()) { entry in
            NextUpWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Up")
        .description("The very next warranty or return deadline.")
        .supportedFamilies([.systemSmall, .accessoryInline])
    }
}
