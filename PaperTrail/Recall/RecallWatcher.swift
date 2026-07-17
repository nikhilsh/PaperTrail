import Foundation
import UserNotifications

/// Persisted per-record recall check result. Not SwiftData-backed — same
/// reasoning as `ManualStore`: this is local-only, derived state that
/// doesn't need to sync or migrate through CloudKit. Small JSON blob in
/// `UserDefaults`, keyed by `PurchaseRecord.id.uuidString`.
nonisolated struct RecallCheckRecord: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case clear
        case notice
    }
    var status: Status
    /// Set only when `status == .notice` — the matched notice's `id`, so the
    /// dossier row can look it up in the cached notice list without
    /// re-fetching the feed.
    var noticeID: String?
    var checkedAt: Date
    /// Whether this result came from `FixtureRecallFeed` rather than a real
    /// feed — carried through to `RowState` so the dossier row can render an
    /// unmistakable "preview data" treatment instead of presenting fixture
    /// matches as genuine recalls. Defaults `false` so an old persisted blob
    /// without this key still decodes (see the `Codable` note below).
    var isFixture: Bool = false

    /// Custom `Decodable` so a result persisted before `isFixture` existed
    /// (missing key) decodes as `false` instead of failing the whole
    /// dictionary decode — `loadResults` would otherwise silently drop every
    /// persisted result the first time this ships.
    enum CodingKeys: String, CodingKey {
        case status, noticeID, checkedAt, isFixture
    }

    init(status: Status, noticeID: String?, checkedAt: Date, isFixture: Bool) {
        self.status = status
        self.noticeID = noticeID
        self.checkedAt = checkedAt
        self.isFixture = isFixture
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Status.self, forKey: .status)
        noticeID = try container.decodeIfPresent(String.self, forKey: .noticeID)
        checkedAt = try container.decode(Date.self, forKey: .checkedAt)
        isFixture = try container.decodeIfPresent(Bool.self, forKey: .isFixture) ?? false
    }
}

/// Background-refresh recall matching (docs/design-v3/V3_BRIEF.md §6).
/// `@MainActor` — reads/writes `UserDefaults` and touches
/// `PlusEntitlements.shared`, matching the project's ambient MainActor
/// default and `PlusEntitlements`' own isolation.
///
/// Hooked into `ForegroundRefreshCoordinator` in `AppShellView.swift`,
/// alongside the existing debounced digest/widget refresh — not a true
/// background-refresh (BGTaskScheduler) integration in this wave; matching
/// only ever runs while the app is foregrounded, at most once per 24h.
@MainActor
enum RecallWatcher {
    private static let resultsKey = "recall.results.v1"
    private static let noticesKey = "recall.notices.v1"
    private static let lastCheckKey = "recall.lastGlobalCheck.v1"
    private static let minRecheckInterval: TimeInterval = 24 * 60 * 60

    /// Dossier row display state (docs/design-v3/V3_BRIEF.md §6). `.checking`
    /// covers both true first-run (no result persisted yet for this record)
    /// and "the flag/Plus gate just turned on and no check has run this
    /// session" — either way there's nothing to show but the first-run
    /// ellipsis text yet. The actual ellipsis *animation* is `animPassV3`
    /// (§9) — out of scope here; this row renders the static "Watching…"
    /// text only.
    nonisolated enum RowState: Equatable {
        case checking
        case clear(checkedAt: Date, isFixture: Bool)
        case notice(RecallNotice, isFixture: Bool)
    }

    /// Current display state for `recordID` — reads persisted state only,
    /// never triggers a check itself. Callers gate on
    /// `FeatureFlags.isOn(.recallWatch) && PlusEntitlements.shared.hasPlus`
    /// before calling this (see `RecordDetailView.recallRow`); the row is
    /// absent entirely when that gate is off.
    static func rowState(for recordID: UUID, defaults: UserDefaults = .standard) -> RowState {
        guard let record = loadResults(defaults: defaults)[recordID.uuidString] else { return .checking }
        switch record.status {
        case .clear:
            return .clear(checkedAt: record.checkedAt, isFixture: record.isFixture)
        case .notice:
            guard let noticeID = record.noticeID,
                  let notice = loadNotices(defaults: defaults)[noticeID] else {
                // Notice cache missing/stale (e.g. cleared defaults) — fall
                // back to "clear" rather than crash or show a broken row.
                return .clear(checkedAt: record.checkedAt, isFixture: record.isFixture)
            }
            return .notice(notice, isFixture: record.isFixture)
        }
    }

    /// Which of `records` a recall check should even consider — pulled out
    /// of `checkIfNeeded` for testability. Passed-on items are no longer
    /// this household's problem: a recall notice on something already
    /// sold/given away isn't actionable and shouldn't cost this owner an
    /// alert. Not `nonisolated` — unlike `shouldNotify` below, this touches
    /// `PurchaseRecord` directly (MainActor-isolated, like the rest of this
    /// type), the same reason `RecallMatcher` routes through a decoupled
    /// `RecordSnapshot` instead of `PurchaseRecord` for ITS pure logic.
    static func eligibleForRecallCheck(_ records: [PurchaseRecord]) -> [PurchaseRecord] {
        records.filter { $0.passedOnDate == nil }
    }

    /// Whether a match should trigger the (cap-exempt) safety notification —
    /// only for a genuinely NEW match against a REAL (non-fixture) feed.
    /// Pulled out of `checkIfNeeded` as a pure decision so it's directly
    /// testable without `UNUserNotificationCenter`: this is the actual
    /// honesty guarantee behind "fixture data never notifies".
    nonisolated static func shouldNotify(isNewMatch: Bool, isFixture: Bool) -> Bool {
        isNewMatch && !isFixture
    }

    /// Runs a recall check across `records` if the flag+Plus gate is on and
    /// the last check was more than 24h ago (or never). No-ops instantly
    /// otherwise — safe to call unconditionally from the foreground hook.
    /// On a feed fetch failure, logs and leaves `lastGlobalCheck` untouched
    /// so the very next foreground retries rather than waiting out the
    /// throttle window on a failed attempt.
    static func checkIfNeeded(
        records: [PurchaseRecord],
        feed: RecallFeedAdapter = FixtureRecallFeed(),
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) async {
        guard FeatureFlags.isOn(.recallWatch), PlusEntitlements.shared.hasPlus else { return }
        if let last = defaults.object(forKey: lastCheckKey) as? Date,
           now.timeIntervalSince(last) < minRecheckInterval {
            return
        }

        let notices: [RecallNotice]
        do {
            notices = try await feed.fetchRecalls()
        } catch {
            AppLogger.error("RecallWatcher: feed fetch failed: \(error.localizedDescription)", category: "recall")
            return
        }

        var noticesByID = loadNotices(defaults: defaults)
        for notice in notices { noticesByID[notice.id] = notice }

        var results = loadResults(defaults: defaults)
        var newMatchCount = 0

        // Passed-on items are no longer this household's problem — a
        // recall notice on something already sold/given away isn't
        // actionable and shouldn't cost this owner an alert.
        for record in eligibleForRecallCheck(records) {
            let snapshot = RecallMatcher.RecordSnapshot(
                recordID: record.id,
                merchantName: record.merchantName,
                productName: record.productName,
                serialNumber: record.serialNumber
            )
            let previous = results[record.id.uuidString]

            if let matched = RecallMatcher.firstMatch(for: snapshot, in: notices) {
                results[record.id.uuidString] = RecallCheckRecord(status: .notice, noticeID: matched.id, checkedAt: now, isFixture: feed.isFixture)
                let alreadyKnown = previous?.status == .notice && previous?.noticeID == matched.id
                if !alreadyKnown { newMatchCount += 1 }
                // Never fire a real, cap-exempt safety notification off
                // fixture data — that would alarm the user over a recall
                // that doesn't exist. See `RecallFeedAdapter.isFixture` and
                // `shouldNotify`.
                if shouldNotify(isNewMatch: !alreadyKnown, isFixture: feed.isFixture) {
                    // Cap-exempt safety notifications schedule regardless of
                    // authorization (see `scheduleSafetyNotification`'s doc)
                    // — that's deliberate, but a denied user will never
                    // actually see it, which must never be a silent drop for
                    // a safety recall. Sentry-warn so it's diagnosable
                    // without a device.
                    let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                    if status == .denied {
                        AppLogger.warn(
                            "RecallWatcher: safety notification scheduled for \(record.id.uuidString) while notifications are denied — it will not be delivered",
                            category: "recall"
                        )
                    }
                    scheduleSafetyNotification(record: record, notice: matched)
                }
            } else {
                results[record.id.uuidString] = RecallCheckRecord(status: .clear, noticeID: nil, checkedAt: now, isFixture: feed.isFixture)
            }
        }

        saveNotices(noticesByID, defaults: defaults)
        saveResults(results, defaults: defaults)
        defaults.set(now, forKey: lastCheckKey)

        AppLogger.info(
            "RecallWatcher: checked \(records.count) record(s) against \(notices.count) notice(s), \(newMatchCount) new match(es)",
            category: "recall"
        )
    }

    // MARK: - Notification (cap-exempt)

    /// Fires on a NEW match only (never re-fires for a notice the record
    /// already matched last check). **Safety notifications are the ONLY
    /// category exempt from PaperTrail's ~2/month notification cap**
    /// (docs/design-v2/DESIGN_LANGUAGE.md §6, docs/design-v3/V3_BRIEF.md
    /// §6/acceptance criteria) — every other notification type in this app
    /// counts toward that budget; this one deliberately doesn't, because a
    /// safety recall overrides the "don't nag" promise.
    private static func scheduleSafetyNotification(record: PurchaseRecord, notice: RecallNotice) {
        let content = UNMutableNotificationContent()
        content.title = "\(record.productName) — safety recall"
        content.body = notice.title
        content.sound = .default
        content.categoryIdentifier = "RECALL_SAFETY"
        content.userInfo = ["recordID": record.id.uuidString, "route": "record"]

        let identifier = "recall-\(record.id.uuidString)"
        // Fire as soon as possible rather than at a specific calendar time —
        // this is a safety alert, not a scheduled reminder.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.error("RecallWatcher: failed to schedule \(identifier): \(error.localizedDescription)", category: "recall")
            }
        }
    }

    // MARK: - Persistence

    private static func loadResults(defaults: UserDefaults) -> [String: RecallCheckRecord] {
        guard let data = defaults.data(forKey: resultsKey),
              let decoded = try? JSONDecoder().decode([String: RecallCheckRecord].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveResults(_ results: [String: RecallCheckRecord], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(results) else { return }
        defaults.set(data, forKey: resultsKey)
    }

    private static func loadNotices(defaults: UserDefaults) -> [String: RecallNotice] {
        guard let data = defaults.data(forKey: noticesKey) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([String: RecallNotice].self, from: data) else { return [:] }
        return decoded
    }

    private static func saveNotices(_ notices: [String: RecallNotice], defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(notices) else { return }
        defaults.set(data, forKey: noticesKey)
    }
}
