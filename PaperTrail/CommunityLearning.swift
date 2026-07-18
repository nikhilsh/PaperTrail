import Foundation
import Synchronization

/// Cross-user ("community") learning pipeline — no human curation anywhere.
///
/// Every install contributes anonymized correction events to a shared Postgres
/// (Supabase REST; see `supabase/schema.sql`), where a scheduled SQL job does
/// **majority learning**: per-merchant facts are recomputed automatically as the
/// mode across ≥3 distinct installs. Devices pull the aggregated
/// `community_merchants` table back and use it as a low-confidence fallback when
/// the user has no personal profile for a merchant.
///
/// Privacy model (anonymized, opt-IN):
/// - Contributions are keyed by a random install UUID — generated locally,
///   never tied to the Apple ID, device id, or iCloud identity.
/// - Only structured field values are sent (merchant key, field, original →
///   corrected), never transcripts or images. Values are scrubbed of
///   email/phone-shaped substrings and length-capped before upload.
/// - The toggle lives in Settings → Your data ("Share anonymous learning
///   data"), OFF by default; a first-launch consent prompt (see
///   `AppShellView`) offers to turn it on. Turning it off stops uploads
///   immediately.
/// - The whole pipeline is dormant until `BuildSecrets.supabaseURL` is
///   configured (CI injects it like the Sentry DSN).
///
/// Delivery model: the local corrections/confirmations JSONL files are the
/// upload queue. `syncBacklog()` uploads everything newer than a per-stream
/// high-water mark and only advances the mark on HTTP success — so failed
/// uploads retry next launch, and opting in late contributes the full local
/// history, not just future saves.
final class CommunityLearning: @unchecked Sendable {

    static let shared = CommunityLearning()

    static let optOutKey = "community.learningEnabled"
    static let contextualAskShownKey = "community.contextualAskShown"
    static let pendingContextualAskKey = "community.pendingContextualAsk"
    static let lastSyncSummaryKey = "community.lastSyncSummary"
    static let correctionsSyncedThroughKey = "community.syncedThroughCorrections"
    static let confirmationsSyncedThroughKey = "community.syncedThroughConfirmations"
    private static let installIDKey = "community.installID"
    private static let cacheFilename = "community_hints.json"
    /// Upload at most this many entries per stream per sync — a backstop for
    /// pathological local logs; the remainder drains on subsequent syncs.
    static let syncBatchCap = 300

    private let session: URLSession
    private let hintsByMerchant = Mutex([String: CommunityMerchantHint]())
    private let syncInFlight = Mutex(false)

    init(session: URLSession = .shared) {
        self.session = session
        UserDefaults.standard.register(defaults: [Self.optOutKey: false])
        loadCachedHints()
    }

    // MARK: - Configuration

    static var isConfigured: Bool {
        !BuildSecrets.supabaseURL.isEmpty && !BuildSecrets.supabaseAnonKey.isEmpty
    }

    /// Opt-out switch (default ON). Honored before any network call.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: optOutKey)
    }

    /// Random, locally-generated install identity — anonymous by construction.
    static var installID: String {
        if let existing = UserDefaults.standard.string(forKey: installIDKey) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: installIDKey)
        return fresh
    }

    // MARK: - Contribution (device → database)

    /// Fire-and-forget trigger for `syncBacklog()` — call sites that can't
    /// await (save flows) use this.
    func scheduleSync() {
        Task { await self.syncBacklog() }
    }

    /// Upload every locally-logged correction/confirmation newer than the
    /// last successful sync. The local JSONL files ARE the queue: nothing is
    /// lost to a flaky network (retried next launch), and a user who opts in
    /// months after their corrections were logged still contributes them all
    /// (the markers start at zero). Runs at launch, on save, and when the
    /// sharing toggle turns on.
    func syncBacklog() async {
        guard Self.isConfigured, Self.isEnabled else { return }
        let alreadyRunning = syncInFlight.withLock { inFlight -> Bool in
            if inFlight { return true }
            inFlight = true
            return false
        }
        guard !alreadyRunning else { return }
        defer { syncInFlight.withLock { $0 = false } }

        let defaults = UserDefaults.standard
        let corrections = Self.pending(
            entries: CorrectionLogger.readAllCorrections(),
            after: defaults.double(forKey: Self.correctionsSyncedThroughKey),
            cap: Self.syncBatchCap
        )
        let confirmations = Self.pending(
            entries: CorrectionLogger.readAllConfirmations(),
            after: defaults.double(forKey: Self.confirmationsSyncedThroughKey),
            cap: Self.syncBatchCap
        )
        let payloads = Self.payloads(from: corrections + confirmations, installID: Self.installID)
        guard !payloads.isEmpty else {
            // A batch of only unuploadable entries (legacy log lines with no
            // merchant key — community rows are keyed by merchant) must not
            // wedge the queue: advance the markers past them so "Pending
            // upload" tells the truth and future syncs start after them.
            let skipped = corrections.count + confirmations.count
            if skipped > 0 {
                if let newest = corrections.map(\.timestamp.timeIntervalSince1970).max() {
                    defaults.set(newest, forKey: Self.correctionsSyncedThroughKey)
                }
                if let newest = confirmations.map(\.timestamp.timeIntervalSince1970).max() {
                    defaults.set(newest, forKey: Self.confirmationsSyncedThroughKey)
                }
                defaults.set("Skipped \(skipped) legacy entries (no merchant key)", forKey: Self.lastSyncSummaryKey)
                AppLogger.info("Community sync: skipped \(skipped) legacy entries without a merchant key", category: "community")
            }
            return
        }

        guard let body = try? JSONEncoder().encode(payloads),
              var request = Self.request(path: "rest/v1/correction_events", method: "POST") else { return }
        request.httpBody = body
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                AppLogger.warn("Community sync rejected: HTTP \(http.statusCode)", category: "community")
                defaults.set("Rejected: HTTP \(http.statusCode)", forKey: Self.lastSyncSummaryKey)
                return
            }
            // Success — advance each stream's high-water mark to the newest
            // entry that was actually in this batch.
            if let newest = corrections.map(\.timestamp.timeIntervalSince1970).max() {
                defaults.set(newest, forKey: Self.correctionsSyncedThroughKey)
            }
            if let newest = confirmations.map(\.timestamp.timeIntervalSince1970).max() {
                defaults.set(newest, forKey: Self.confirmationsSyncedThroughKey)
            }
            defaults.set("Uploaded \(corrections.count) corrections · \(confirmations.count) confirmations", forKey: Self.lastSyncSummaryKey)
            AppLogger.info("Community sync: uploaded \(corrections.count) corrections, \(confirmations.count) confirmations", category: "community")
        } catch {
            AppLogger.warn("Community sync failed: \(error.localizedDescription)", category: "community")
            defaults.set("Failed: \(error.localizedDescription)", forKey: Self.lastSyncSummaryKey)
        }
    }

    /// Entries strictly newer than the marker, oldest first, capped so the
    /// marker only ever advances over what was actually uploaded. Pure —
    /// unit-tested directly.
    static func pending(
        entries: [CorrectionLogger.CorrectionEntry],
        after syncedThrough: TimeInterval,
        cap: Int
    ) -> [CorrectionLogger.CorrectionEntry] {
        Array(
            entries
                .filter { $0.timestamp.timeIntervalSince1970 > syncedThrough }
                .sorted { $0.timestamp < $1.timestamp }
                .prefix(cap)
        )
    }

    /// Entries that can actually ship — community rows are keyed by merchant,
    /// so legacy log lines without one can never upload. Pure — unit-tested.
    static func uploadable(_ entries: [CorrectionLogger.CorrectionEntry]) -> [CorrectionLogger.CorrectionEntry] {
        entries.filter { !($0.merchant ?? "").isEmpty }
    }

    /// How many locally-logged entries haven't reached the community yet —
    /// surfaced in Advanced Diagnostics. Counts only entries that CAN upload,
    /// so unshippable legacy lines don't read as a stuck queue.
    static func pendingUploadCount() -> Int {
        let defaults = UserDefaults.standard
        return uploadable(pending(entries: CorrectionLogger.readAllCorrections(),
                                  after: defaults.double(forKey: correctionsSyncedThroughKey),
                                  cap: .max)).count
             + uploadable(pending(entries: CorrectionLogger.readAllConfirmations(),
                                  after: defaults.double(forKey: confirmationsSyncedThroughKey),
                                  cap: .max)).count
    }

    /// Build wire payloads from local entries: scrubbed, capped, anonymous.
    /// Pure — unit-tested directly.
    static func payloads(from entries: [CorrectionLogger.CorrectionEntry], installID: String) -> [ContributionPayload] {
        entries.compactMap { entry in
            guard let merchant = entry.merchant, !merchant.isEmpty else { return nil }
            return ContributionPayload(
                installId: installID,
                merchantKey: merchant,
                fieldName: entry.fieldName,
                originalValue: scrub(entry.originalValue),
                correctedValue: scrub(entry.correctedValue),
                documentKind: entry.documentKind,
                source: entry.source,
                confidence: entry.confidence
            )
        }
    }

    /// Remove email- and phone-shaped substrings and cap length, so even the
    /// rare personal string typed into a field never reaches the database.
    static func scrub(_ value: String) -> String {
        var scrubbed = value
        for pattern in [
            #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,   // emails
            #"\+?\d[\d\s-]{6,}\d"#,                                // phone-ish digit runs
        ] {
            scrubbed = scrubbed.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
        if scrubbed.count > 120 {
            scrubbed = String(scrubbed.prefix(120)) + "…"
        }
        return scrubbed
    }

    struct ContributionPayload: Codable, Sendable {
        let installId: String
        let merchantKey: String
        let fieldName: String
        let originalValue: String
        let correctedValue: String
        let documentKind: String
        let source: String
        let confidence: String

        enum CodingKeys: String, CodingKey {
            case installId = "install_id"
            case merchantKey = "merchant_key"
            case fieldName = "field_name"
            case originalValue = "original_value"
            case correctedValue = "corrected_value"
            case documentKind = "document_kind"
            case source
            case confidence
        }
    }

    // MARK: - Community hints (database → device)

    /// Pull the majority-aggregated merchant facts and cache them locally.
    /// Called once per launch; cheap (a few KB).
    func refreshCommunityHints() async {
        guard Self.isConfigured, Self.isEnabled,
              let request = Self.request(path: "rest/v1/community_merchants?select=*", method: "GET") else { return }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode < 300 else { return }
            let hints = try Self.decodeHints(data)
            hintsByMerchant.withLock { $0 = hints }
            try? data.write(to: Self.cacheURL, options: .atomic)
            AppLogger.info("Community hints refreshed: \(hints.count) merchants", category: "community")
        } catch {
            AppLogger.info("Community hint refresh failed: \(error.localizedDescription)", category: "community")
        }
    }

    /// The community's majority-learned facts for a merchant, if any.
    func hint(forNormalizedMerchant merchant: String?) -> CommunityMerchantHint? {
        guard let merchant, !merchant.isEmpty, Self.isEnabled else { return nil }
        return hintsByMerchant.withLock { $0[merchant] }
    }

    static func decodeHints(_ data: Data) throws -> [String: CommunityMerchantHint] {
        let rows = try JSONDecoder().decode([CommunityMerchantHint].self, from: data)
        return Dictionary(rows.map { ($0.merchantKey, $0) }, uniquingKeysWith: { lhs, _ in lhs })
    }

    private static var cacheURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(cacheFilename)
    }

    private func loadCachedHints() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let hints = try? Self.decodeHints(data) else { return }
        hintsByMerchant.withLock { $0 = hints }
    }

    private static func request(path: String, method: String) -> URLRequest? {
        guard let url = URL(string: "\(BuildSecrets.supabaseURL)/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(BuildSecrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(BuildSecrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}

/// One row of the majority-aggregated `community_merchants` table.
struct CommunityMerchantHint: Codable, Sendable {
    let merchantKey: String
    let displayName: String?
    let documentKind: String?
    let currency: String?
    let category: String?
    let contributors: Int

    enum CodingKeys: String, CodingKey {
        case merchantKey = "merchant_key"
        case displayName = "display_name"
        case documentKind = "document_kind"
        case currency
        case category
        case contributors
    }

    /// Convert to a learning context. Community knowledge is NEVER
    /// authoritative: confidence scales with contributor count but caps at
    /// 0.45 — below the 0.6 auto-apply threshold, so it phrases FM hints
    /// tentatively and personal profiles always outrank it.
    func learningContext() -> MerchantLearningContext {
        MerchantLearningContext(
            profileID: nil,
            normalizedMerchantName: merchantKey,
            displayMerchantName: displayName,
            categorySuggestion: category,
            currencySuggestion: currency,
            warrantySuggestionMonths: nil,
            amountHint: nil,
            dateHint: nil,
            productHint: nil,
            likelyDocumentKind: documentKind.flatMap { DocumentKind(rawValue: $0) },
            confidence: min(0.45, Double(contributors) * 0.1)
        )
    }
}
