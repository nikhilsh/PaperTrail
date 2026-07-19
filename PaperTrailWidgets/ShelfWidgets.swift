import WidgetKit
import SwiftUI

// MARK: - v3 shelfWidgets (Ideas C1, corrected per BUILD_REVIEW W1–W7)
//
// The v3 widget kinds behind `FeatureFlags.isOn(.shelfWidgets)`
// (`docs/design-v3/V3_BRIEF.md` §1): a medium paper "Closing soon" card, a
// small paper coverage ring, a small dark "Next up" card (which also
// supplies the `.accessoryInline` Lock Screen family), and a Lock Screen
// circular "Quick Shelve" scanner shortcut. All reuse
// `ExpiringSoonProvider`/`ExpiringSoonEntry` from `ExpiringSoonWidget.swift`
// — one snapshot-loading path for every widget kind in the extension — and
// are added to the `WidgetBundle` in `PaperTrailWidgetsBundle.swift`.
//
// Remaining/absolute-date phrasing routes through `CoverageFormatter`
// (mirrored from `PaperTrail/Design/CoverageFormatter.swift`) so the same
// number never renders as "321 days" here and "10 mo" in the app
// (BUILD_REVIEW W2/W7). The v2 `ExpiringSoonWidget` keeps its own compact
// `ExpiringSoonFormatting` phrasing untouched — that surface is
// APPSTORE-frozen.
//
// The `WidgetBundle` composition is static: within a non-APPSTORE build
// these kinds always appear in the widget gallery, flag or no flag
// (WidgetKit has no runtime way to hide a bundle member). When the flag is
// off, the home-screen views here render "Enable in Settings → Flags"
// rather than the v2 widget's genuine no-data fallback ("Open PaperTrail
// to update") — the two states need distinct copy so a user can tell
// "feature disabled" from "broken". Quick Shelve is the one exception: a
// circular accessory has no room for that copy, and its deep link is
// harmless with the flag off (it just opens the app).
//
// **APPSTORE builds compile these kinds out of the bundle entirely**
// (`PaperTrailWidgetsBundle`'s `#if APPSTORE` split) — the v3 widget kind
// existing at all is itself a surface an App Store binary must be provably
// free of.

private let shelfPaperBackground = LinearGradient(
    colors: [WidgetPalette.paperTop, WidgetPalette.paperBottom],
    startPoint: .top,
    endPoint: .bottom
)

// MARK: - Paper empty state

/// The cream/paper counterpart to `EmptyStateView` — used by the "Closing
/// soon" and coverage-ring widgets, which render on the paper background
/// rather than the dark one. Reserved for "can't show anything" (flag off,
/// snapshot unreadable, empty library) — a library with nothing closing
/// soon gets `ClosingSoonQuietView` instead, which is good news, not a
/// fallback.
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

/// The "34 days"/"today"/"expired" pill next to each closing-soon row,
/// colored by real state (BUILD_REVIEW W1 — amber is a state, not a
/// decoration): terra under a week or expired, amber under 60 days, sage
/// beyond that (rare here, since warranty rows are pre-filtered to ≤ 60
/// days, but a long return window can exceed it). The pill TEXT uses the
/// deeper variants for contrast on cream; the dot keeps the base color.
private struct UrgencyPill: View {
    let daysLeft: Int

    private var dotColor: Color {
        if daysLeft < 7 { return WidgetPalette.terra }
        if daysLeft < 60 { return WidgetPalette.amber }
        return WidgetPalette.sage
    }

    private var textColor: Color {
        if daysLeft < 7 { return WidgetPalette.terraDeep }
        if daysLeft < 60 { return WidgetPalette.amberDeep }
        return WidgetPalette.sageDeep
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(dotColor).frame(width: 5, height: 5)
            Text(CoverageFormatter.remaining(days: daysLeft))
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(dotColor.opacity(0.16), in: Capsule())
    }
}

/// One "closing soon" row — a return window or a warranty deadline, sharing
/// one visual treatment (name + kind-specific subtitle + day-count pill) so
/// both can sit together at the same density as the dark ExpiringSoon
/// medium widget's `MediumWidgetRow`, without singling out returns the way
/// the old return-only row did.
private struct ClosingSoonItemRow: View {
    let item: WidgetSnapshotItem
    let asOf: Date

    /// Year included only when the date is far out (W7) — "3 Jun" for a
    /// return window, "3 Jun 2027" for a warranty a year away.
    private var subtitle: String {
        let dateText = CoverageFormatter.absoluteDate(item.date, asOf: asOf)
        return item.kind == "return"
            ? "Last day to change your mind: \(dateText)"
            : "Warranty ends \(dateText)"
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

/// The rows that genuinely qualify as "closing soon" (BUILD_REVIEW W1 —
/// never manufacture urgency): return windows always count while upcoming
/// (they're short by nature), warranty expiries only within 60 days. An
/// item 321 days out is covered, not closing — it belongs to the quiet
/// state, not an amber row. `entry.items` arrive nearest-first from
/// `WidgetSnapshotWriter.nearestUpcoming`, so the filter preserves that
/// order. The register nudge rides along as a bonus row when there's room
/// left under the cap — it never bumps a genuine deadline out.
private struct ClosingSoonRows {
    let items: [WidgetSnapshotItem]
    let registerNudge: WidgetRegisterNudge?

    /// systemMedium fits the header plus TWO ~30pt rows and one divider —
    /// three rows overflowed the canvas and clipped the bottom row on
    /// device (build 39). The nudge only rides along when it fits in the
    /// two-row budget, i.e. when there's at most one real item.
    init(entry: ExpiringSoonEntry) {
        let qualifying = entry.items.filter { item in
            item.kind == "return"
                || CoverageFormatter.daysLeft(from: entry.date, to: item.date) <= 60
        }
        let capped = Array(qualifying.prefix(2))
        items = capped
        registerNudge = capped.count < 2 ? entry.registerNudge : nil
    }

    var isEmpty: Bool { items.isEmpty && registerNudge == nil }
}

/// The sage "everything's fine" pill on the quiet card — deep text on a
/// sage-tinted capsule for contrast on cream, dot in base sage, same
/// anatomy as `UrgencyPill`.
private struct AllCoveredPill: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(WidgetPalette.sage).frame(width: 5, height: 5)
            Text("ALL COVERED")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(WidgetPalette.sageDeep)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(WidgetPalette.sage.opacity(0.18), in: Capsule())
    }
}

/// The quiet state is the DEFAULT design for this card, not an error
/// (BUILD_REVIEW W1): with the 60-day qualifier most libraries have
/// nothing closing soon most of the time, and that's good news — headline
/// it, note the next expiry so the card still informs, and close with the
/// portfolio line. Only rendered when the snapshot decoded and the library
/// is non-empty; "can't read data"/"no records" still fall back to
/// `PaperEmptyStateView`.
private struct ClosingSoonQuietView: View {
    let entry: ExpiringSoonEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PAPERTRAIL · CLOSING SOON")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(WidgetPalette.goldDeep)

            Spacer(minLength: 4)

            Text("Nothing closing soon.")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(WidgetPalette.ink)

            if let next = entry.items.first {
                Text("Next: \(next.name) · \(CoverageFormatter.absoluteDate(next.date, asOf: entry.date))")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.inkSecondary)
                    .lineLimit(1)
                    .privacySensitive()
            }

            Spacer(minLength: 4)

            HStack(alignment: .center, spacing: 8) {
                Text(footerText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(WidgetPalette.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
                Spacer(minLength: 8)
                if isAllCovered {
                    AllCoveredPill()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(shelfPaperBackground, for: .widget)
    }

    /// "5 ITEMS · S$3.1k ON FILE" — value part prefers the compact form so
    /// it never truncates, same fallback rule as the coverage ring's
    /// caption; drops the value entirely for a snapshot with no amounts.
    private var footerText: String {
        let total = entry.totalCount ?? 0
        let itemsPart = total == 1 ? "1 ITEM" : "\(total) ITEMS"
        guard let valueText = entry.totalValueCompactText ?? entry.totalValueText else {
            return "\(itemsPart) ON FILE"
        }
        return "\(itemsPart) · \(valueText) ON FILE"
    }

    private var isAllCovered: Bool {
        guard let total = entry.totalCount, total > 0 else { return false }
        return entry.coveredCount == total
    }
}

private struct ClosingSoonWidgetView: View {
    let entry: ExpiringSoonEntry

    var body: some View {
        if !FeatureFlags.isOn(.shelfWidgets) {
            PaperEmptyStateView(message: "Enable in Settings → Flags")
        } else {
            let rows = ClosingSoonRows(entry: entry)
            if !rows.isEmpty {
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
            } else if entry.isDataAvailable, let total = entry.totalCount, total > 0 {
                ClosingSoonQuietView(entry: entry)
            } else {
                PaperEmptyStateView(message: entry.emptyStateMessage)
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
        .description("How many of your records are still under warranty.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Next up (small dark + accessoryInline)

/// W6 dark chrome: the spec's ink gradient plus a 0.5pt cream hairline,
/// drawn inside the `containerBackground` closure so the hairline hugs the
/// system container shape at whatever corner radius the device uses.
/// Replaces the flat near-black `WidgetPalette.background`, which stays for
/// the untouched v2 APPSTORE widget.
private struct NextUpChrome: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [WidgetPalette.inkChromeTop, WidgetPalette.inkChromeBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            ContainerRelativeShape()
                .strokeBorder(WidgetPalette.cream.opacity(0.22), lineWidth: 0.5)
        }
    }
}

/// "Next up"'s own flag-off/no-data state — same copy anatomy as
/// `EmptyStateView` but carrying the W6 chrome. Deliberately NOT reusing
/// `EmptyStateView` itself: that view is part of the pixel-frozen v2
/// APPSTORE surface and must not change.
private struct NextUpEmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 4) {
            Text("PaperTrail")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WidgetPalette.gold)
            Text(message)
                .font(.footnote)
                .foregroundStyle(WidgetPalette.cream)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { NextUpChrome() }
    }
}

/// BUILD_REVIEW W3: the serif headline is the ITEM NAME — never a
/// truncated event-type word ("Warranty…"). The stake goes in the
/// subtitle with the year rule (W7), and the remaining time closes as a
/// mono gold footer.
private struct NextUpSmallView: View {
    let entry: ExpiringSoonEntry

    var body: some View {
        if let item = entry.items.first {
            let daysLeft = ExpiringSoonFormatting.daysLeft(from: entry.date, to: item.date)
            VStack(alignment: .leading, spacing: 6) {
                Text("NEXT UP")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(WidgetPalette.gold)

                Text(item.name)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(WidgetPalette.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .privacySensitive()

                Text(stakeText(for: item))
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.cream.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                Text(CoverageFormatter.remainingLeft(days: daysLeft).uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(WidgetPalette.gold)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { NextUpChrome() }
            .widgetURL(ExpiringSoonFormatting.deepLink(for: item))
        } else {
            NextUpEmptyStateView(message: entry.emptyStateMessage)
        }
    }

    /// "Warranty ends 3 Jun 2027" / "Return window closes 22 Jul" — year
    /// only when the date is far out (W7).
    private func stakeText(for item: WidgetSnapshotItem) -> String {
        let dateText = CoverageFormatter.absoluteDate(item.date, asOf: entry.date)
        return item.kind == "return"
            ? "Return window closes \(dateText)"
            : "Warranty ends \(dateText)"
    }
}

private struct NextUpAccessoryInlineView: View {
    let entry: ExpiringSoonEntry

    var body: some View {
        Text(inlineText)
            .privacySensitive()
    }

    /// One Lock Screen line: the per-item countdown only when something is
    /// genuinely near (≤ 14 days — same "don't manufacture urgency" rule
    /// as W1), otherwise the portfolio summary ("5 items covered · next:
    /// Jun 2027"). A pre-v3 snapshot (no coverage fields) keeps the old
    /// per-item line, reworded through `CoverageFormatter`.
    private var inlineText: String {
        let nearest = entry.items.first
        if let item = nearest {
            let daysLeft = ExpiringSoonFormatting.daysLeft(from: entry.date, to: item.date)
            if daysLeft <= 14 {
                return "\(item.name) · \(CoverageFormatter.remainingLeft(days: daysLeft))"
            }
        }
        if let covered = entry.coveredCount {
            let coveredPart = covered == 1 ? "1 item covered" : "\(covered) items covered"
            if let nextWarranty = entry.items.first(where: { $0.kind == "warranty" }) {
                return "\(coveredPart) · next: \(CoverageFormatter.monthYear(nextWarranty.date))"
            }
            return coveredPart
        }
        if let item = nearest {
            let daysLeft = ExpiringSoonFormatting.daysLeft(from: entry.date, to: item.date)
            return "\(item.name) · \(CoverageFormatter.remainingLeft(days: daysLeft))"
        }
        return entry.emptyStateMessage
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
                NextUpEmptyStateView(message: "Enable in Settings → Flags")
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

// MARK: - Quick shelve (accessoryCircular)

/// Lock Screen shortcut straight into the scanner — `papertrail://capture`
/// is the same deep link the app already routes to the capture flow.
/// Deliberately NOT gated on `FeatureFlags.isOn(.shelfWidgets)`: a circular
/// accessory has no room for "Enable in Settings → Flags" copy, and the
/// deep link is harmless with the flag off (it just opens the app). Gold
/// renders only where the Lock Screen allows color; elsewhere the system
/// tints the glyph.
private struct QuickShelveView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "archivebox")
                .font(.title3.weight(.semibold))
                .foregroundStyle(WidgetPalette.gold)
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(URL(string: "papertrail://capture"))
    }
}

struct QuickShelveWidget: Widget {
    let kind: String = "QuickShelveWidget"

    var body: some WidgetConfiguration {
        // The provider's entry is unused — this widget is a static button —
        // but sharing `ExpiringSoonProvider` keeps the extension on its one
        // snapshot-loading path rather than introducing a second provider.
        StaticConfiguration(kind: kind, provider: ExpiringSoonProvider()) { _ in
            QuickShelveView()
        }
        .configurationDisplayName("Quick Shelve")
        .description("Scan a receipt straight into PaperTrail.")
        .supportedFamilies([.accessoryCircular])
    }
}
