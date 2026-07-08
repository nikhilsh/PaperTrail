import Foundation

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
final class CommunityLearning: @unchecked Sendable {

    static let shared = CommunityLearning()

    static let optOutKey = "community.learningEnabled"
    private static let installIDKey = "community.installID"
    private static let cacheFilename = "community_hints.json"

    private let session: URLSession
    private var hintsByMerchant: [String: CommunityMerchantHint] = [:]
    private let lock = NSLock()

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

    /// Fire-and-forget upload of anonymized correction events. Called from the
    /// save flow right after corrections are logged locally.
    func contribute(entries: [CorrectionLogger.CorrectionEntry]) {
        guard Self.isConfigured, Self.isEnabled, !entries.isEmpty else { return }
        let payloads = Self.payloads(from: entries, installID: Self.installID)
        guard !payloads.isEmpty,
              let body = try? JSONEncoder().encode(payloads),
              var request = Self.request(path: "rest/v1/correction_events", method: "POST") else { return }
        request.httpBody = body
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let task = session.dataTask(with: request) { _, response, error in
            if let error {
                AppLogger.info("Community contribution failed: \(error.localizedDescription)", category: "community")
            } else if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                AppLogger.info("Community contribution rejected: HTTP \(http.statusCode)", category: "community")
            }
        }
        task.resume()
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
            lock.lock()
            hintsByMerchant = hints
            lock.unlock()
            try? data.write(to: Self.cacheURL, options: .atomic)
            AppLogger.info("Community hints refreshed: \(hints.count) merchants", category: "community")
        } catch {
            AppLogger.info("Community hint refresh failed: \(error.localizedDescription)", category: "community")
        }
    }

    /// The community's majority-learned facts for a merchant, if any.
    func hint(forNormalizedMerchant merchant: String?) -> CommunityMerchantHint? {
        guard let merchant, !merchant.isEmpty, Self.isEnabled else { return nil }
        lock.lock(); defer { lock.unlock() }
        return hintsByMerchant[merchant]
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
        hintsByMerchant = hints
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
