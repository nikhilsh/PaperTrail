import SwiftUI
import SwiftData

/// The "am I covered?" dashboard. Backed entirely by `PurchaseRecord.warrantyStatus`.
struct WarrantyView: View {
    @Query private var records: [PurchaseRecord]

    /// v3 passItOn (docs/design-v3/V3_BRIEF.md §7, flagged): every
    /// aggregation on this screen (needs-attention/resting-easy lists, the
    /// digest) reads through this rather than `records` directly, so a
    /// passed-on item stops being nagged about — it's not owned anymore.
    /// Collapses back to `records` exactly when the flag is off.
    private var activeRecords: [PurchaseRecord] {
        records.filter { !PassItOnAggregation.isExcludedFromAggregates(passedOnDate: $0.passedOnDate, flagOn: FeatureFlags.isOn(.passItOn)) }
    }

    /// Expired + expiring, sorted by risk: expired first, then soonest-expiring.
    private var needsAttention: [PurchaseRecord] {
        activeRecords
            .filter { $0.warrantyStatus == .expired || $0.warrantyStatus == .expiringSoon }
            .sorted { lhs, rhs in
                func rank(_ r: PurchaseRecord) -> Int { r.warrantyStatus == .expired ? 0 : 1 }
                if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
                return (lhs.warrantyExpiryDate ?? .distantFuture) < (rhs.warrantyExpiryDate ?? .distantFuture)
            }
    }

    private var restingEasy: [PurchaseRecord] {
        activeRecords
            .filter { $0.warrantyStatus == .active }
            .sorted { ($0.warrantyExpiryDate ?? .distantFuture) < ($1.warrantyExpiryDate ?? .distantFuture) }
    }

    private var hasWarranties: Bool {
        activeRecords.contains { $0.warrantyExpiryDate != nil }
    }

    private var digestSummary: DigestSummary {
        DigestBuilder.build(from: activeRecords.map(\.digestSnapshot))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Warranty")
                    .font(PTFont.serif(34, weight: 600))
                    .foregroundStyle(PT.txt)
                    .padding(.top, 8)

                if !digestSummary.isEmpty {
                    DigestCard(summary: digestSummary)
                }

                if !hasWarranties {
                    emptyState
                } else {
                    if !needsAttention.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionLabel(text: "Needs attention", tone: PT.terra)
                            ForEach(needsAttention) { record in
                                AttentionCard(record: record)
                            }
                        }
                    }

                    if !restingEasy.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionLabel(text: "Resting easy", tone: PT.sage)
                            RestingEasyCard(records: restingEasy)
                        }
                    }
                }
            }
            .padding(.horizontal, PT.Metric.screenPad)
            .padding(.bottom, 120)
        }
        .ptScreen()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(PT.txt3)
            Text("No warranties tracked yet.")
                .font(PTFont.serif(18, weight: 500))
                .foregroundStyle(PT.txt2)
            Text("Add a warranty expiry to a record and it\nwill show up here.")
                .font(.system(size: 13))
                .foregroundStyle(PT.txt3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Needs-attention card

private struct AttentionCard: View {
    let record: PurchaseRecord
    private var warranty: PTWarranty { PTWarranty(record: record) }

    private var stampTone: Color {
        record.warrantyStatus == .expired ? PT.terra : PT.amber
    }

    private var stampText: String {
        if record.warrantyStatus == .expired { return "Expired" }
        return warranty.remainingShort   // e.g. "28 days left"
    }

    /// "9 months left" / "Lapsed 4 months ago" — the human warranty line.
    private var leftLine: String {
        guard let expiry = record.warrantyExpiryDate else { return "No warranty" }
        if record.warrantyStatus == .expired {
            return "Lapsed \(PTWarranty.relativePast(expiry))"
        }
        return warranty.remainingShort
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                GlyphTile(symbol: warranty.glyph, size: 36, onPaper: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.displayProductName)
                        .font(PTFont.serif(16, weight: 600))
                        .foregroundStyle(PT.onPaper)
                        .lineLimit(2)
                    Text(leftLine)
                        .font(PTFont.mono(10.5))
                        .foregroundStyle(PT.onPaper2)
                }
                Spacer(minLength: 8)
                StampBadge(text: stampText, tone: stampTone, compact: true)
            }

            WarrantyProgressBar(progress: warranty.progressElapsed, tone: warranty.status.tone)

            if record.warrantyStatus == .expired {
                NavigationLink {
                    SupportView(record: record)
                } label: {
                    Text("Get support")
                }
                .buttonStyle(PTDarkButtonStyle(fullWidth: true))
            } else {
                NavigationLink {
                    WarrantyAnswerView(record: record)
                } label: {
                    Text("View warranty")
                }
                .buttonStyle(PTDarkButtonStyle(fullWidth: true))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: true)
    }
}

// MARK: - Resting-easy card

private struct RestingEasyCard: View {
    let records: [PurchaseRecord]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                let warranty = PTWarranty(record: record)
                NavigationLink {
                    WarrantyAnswerView(record: record)
                } label: {
                    HStack(spacing: 12) {
                        GlyphTile(symbol: warranty.glyph, size: 34, onPaper: true)
                        Text(record.displayProductName)
                            .font(PTFont.serif(16, weight: 500))
                            .foregroundStyle(PT.onPaper)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(warranty.remainingShort)
                            .font(PTFont.mono(10.5, medium: true))
                            .foregroundStyle(PT.sageDeep)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < records.count - 1 {
                    Rectangle().fill(PT.onPaperHair).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(goldFold: false)
    }
}

// MARK: - "This month" digest card

/// The same signal as the monthly notification, surfaced in-app so it isn't
/// notification-only: the headline plus up to 3 soonest-expiring warranties.
/// Compact, no new navigation.
private struct DigestCard: View {
    let summary: DigestSummary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animPassOn: Bool { AnimPass.isOn }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel(text: "This month")
            SettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    Text(summary.headline)
                        .font(.system(size: 13))
                        .foregroundStyle(PT.txt2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, summary.soonestExpiring.isEmpty ? 0 : 12)

                    ForEach(Array(summary.soonestExpiring.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Rectangle().fill(PT.hair2).frame(height: 1).padding(.vertical, 8)
                        }
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.system(size: 13))
                                .foregroundStyle(PT.txt)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(item.daysLeft == 0 ? "today" : "\(item.daysLeft)d left")
                                .font(PTFont.mono(11, medium: true))
                                .foregroundStyle(PT.amber)
                                // v3 animPassV3 §9 #8 "Odometer numbers":
                                // digest stats roll when they change.
                                // Reduce Motion: swap the transition itself,
                                // not just the curve — `.numericText()` rolls
                                // regardless of `.animation`'s duration
                                // (item 10).
                                .contentTransition(animPassOn && !reduceMotion ? .numericText() : .identity)
                                .animation(
                                    animPassOn ? AnimPass.animation(.default, reduceMotion: reduceMotion) : nil,
                                    value: item.daysLeft
                                )
                        }
                    }
                }
                .padding(16)
            }
        }
        // animPassV3 §9 #9's corner-curl reveal is retired: the
        // rotation3DEffect approximation read as a broken skew on device
        // and replayed on every tab visit (device feedback, build 40).
        // The card renders settled; the odometer roll above stays.
    }
}

#Preview {
    NavigationStack { WarrantyView() }
        .environmentObject(CloudImageSyncManager.shared)
        .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
