import SwiftUI

// MARK: - Settings atoms
//
// The new atoms introduced by the Settings & Trust wave: a grouped dark card,
// a mono section label, a settings row (icon tile + title/subtitle + accessory),
// an avatar/initials circle, and the honest backup-status badge. Built on the
// existing "The Archive" tokens so they sit alongside PaperCard/GoldRule/etc.

/// A grouped dark card — the container for settings rows.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(PT.inkCardDark, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PT.hair, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Mono, uppercase, gold-deep section label sitting above a `SettingsCard`.
struct SettingsSectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .ptMonoLabel(10.5, tracking: 2.4)
            .foregroundStyle(PT.goldDeep)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 9)
    }
}

/// Hairline divider drawn between rows inside a `SettingsCard`.
struct SettingsRowDivider: View {
    var body: some View {
        Rectangle().fill(PT.hair2).frame(height: 1).padding(.leading, 16)
    }
}

/// A single settings row: optional icon tile, title + subtitle, and a trailing
/// accessory (value text, chevron, and/or a toggle). When `action` is set (and
/// there's no toggle) the whole row is tappable.
struct SettingsRow: View {
    var icon: String? = nil
    var iconColor: Color = PT.txt2
    var title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueColor: Color = PT.txt3
    var showChevron: Bool = false
    var toggle: Binding<Bool>? = nil
    var danger: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        if let action, toggle == nil {
            Button(action: action) { rowContent }.buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 13) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
                    .frame(width: 30, height: 30)
                    .background(Color(hex: 0xE7DCC4, alpha: 0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(PT.hair2, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .fontWeight(danger ? .semibold : .regular)
                    .foregroundStyle(danger ? PT.terra : PT.txt)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(PT.txt3)
                }
            }
            Spacer(minLength: 8)
            accessoryView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var accessoryView: some View {
        HStack(spacing: 6) {
            if let value {
                Text(value).font(PTFont.mono(12.5)).foregroundStyle(valueColor).lineLimit(1)
            }
            if showChevron { chevron }
            if let toggle {
                Toggle("", isOn: toggle).labelsHidden().tint(PT.sage)
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(PT.txt3)
    }
}

/// Gold-foil avatar circle. Shows the person's initials when known, else a glyph.
struct PTAvatar: View {
    var initials: String? = nil
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [PT.goldHi, PT.goldDeep], startPoint: .top, endPoint: .bottom))
            if let initials, !initials.isEmpty {
                Text(initials)
                    .font(PTFont.serif(size * 0.4, weight: 600))
                    .foregroundStyle(PT.inkStamp)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(PT.inkStamp)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
}

extension String {
    /// Up to two uppercase initials from a display name (e.g. "Alex Rivera" → "AR").
    var ptInitials: String {
        let parts = split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}

// MARK: - Honest backup status (§7)
//
// Replaces the permanent "Backed up · just now" with real Synced / Syncing /
// Paused states, derived from the CloudKit fallback flag + the image sync
// manager's live transfer/error state.

enum BackupState {
    case synced(relative: String)
    case syncing(remaining: Int)
    case paused
    /// No sync has ever completed and none is in flight right now — the
    /// honest state for a fresh install/record before the first backup
    /// lands. NEVER collapsed into `.synced` with a fabricated "just now"
    /// (§6): that reads as a promise already kept when it hasn't been yet.
    case neverSynced

    var dotColor: Color {
        switch self {
        case .synced: PT.sageDeep
        case .syncing: PT.goldDeep
        case .paused: PT.terra
        case .neverSynced: PT.txt3
        }
    }

    var text: String {
        switch self {
        case let .synced(relative): "Backed up · \(relative)"
        case let .syncing(remaining): "Backing up · \(remaining) to go"
        case .paused: "Backup paused · tap to retry"
        case .neverSynced: "Not backed up yet"
        }
    }

    var isPaused: Bool { if case .paused = self { return true }; return false }
}

/// Computes the honest backup state from the available sync signals. A
/// `nil` `lastSync` — no completed sync yet — is `.neverSynced`, never a
/// fabricated `.synced(relative: "just now")` (§6): the timestamp is only
/// ever stamped by the caller (`PaperTrailApp.syncCloudImages`) on an
/// actually-successful round, so `nil` here means truthfully "hasn't
/// happened".
@MainActor
func currentBackupState(
    syncManager: CloudImageSyncManager,
    activeSyncBackend: String,
    lastSync: Date?
) -> BackupState {
    if !syncManager.activeTransfers.isEmpty {
        return .syncing(remaining: syncManager.activeTransfers.count)
    }
    if activeSyncBackend == "Local fallback" || !syncManager.transferErrors.isEmpty {
        return .paused
    }
    guard let lastSync else {
        return .neverSynced
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    let relative = formatter.localizedString(for: lastSync, relativeTo: .now)
    return .synced(relative: relative)
}

/// The library-card footer badge: a tinted dot + mono status line. Tappable
/// (to retry) only when paused.
struct BackupStatusBadge: View {
    let state: BackupState
    var onRetry: () -> Void

    var body: some View {
        if state.isPaused {
            Button(action: onRetry) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.dotColor)
                .frame(width: 7, height: 7)
                .background(Circle().fill(state.dotColor.opacity(0.22)).frame(width: 13, height: 13))
            Text(state.text)
                .font(PTFont.mono(10.5, medium: state.isPaused))
                .foregroundStyle(state.dotColor)
                .lineLimit(1)
        }
    }
}
