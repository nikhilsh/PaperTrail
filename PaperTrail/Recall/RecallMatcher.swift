import Foundation

/// Pure, nonisolated matching between a record and a recall notice — no
/// SwiftData, no I/O, so it's directly unit-testable (`RecallWatcherTests`).
/// `RecallWatcher` is the only caller in the app.
enum RecallMatcher {
    /// Plain value snapshot of the fields a record is matched on. Decoupled
    /// from SwiftData on purpose, same rationale as `DigestRecordSnapshot`.
    nonisolated struct RecordSnapshot: Sendable {
        var recordID: UUID
        var merchantName: String?
        var productName: String
        var serialNumber: String?

        nonisolated init(recordID: UUID, merchantName: String?, productName: String, serialNumber: String?) {
            self.recordID = recordID
            self.merchantName = merchantName
            self.productName = productName
            self.serialNumber = serialNumber
        }
    }

    /// The first notice (in `notices` order) that matches `record`, or `nil`.
    /// A record matches a notice when its brand matches AND its model
    /// matches — both required, per V3_BRIEF §6.
    nonisolated static func firstMatch(for record: RecordSnapshot, in notices: [RecallNotice]) -> RecallNotice? {
        notices.first { matches(record, notice: $0) }
    }

    nonisolated static func matches(_ record: RecordSnapshot, notice: RecallNotice) -> Bool {
        brandMatches(record, notice: notice) && modelMatches(record, notice: notice)
    }

    /// Brand match: normalizes both sides the same way
    /// `SupportContactDirectory.normalize` does (lowercase, alphanumeric
    /// only) and compares the notice's brand against the record's merchant
    /// name and the first few tokens of its product name — mirroring
    /// `SupportContactDirectory.match`'s candidate list, but checked
    /// directly against the notice's own `brand` string rather than routed
    /// through that directory's fixed ~60-brand list, since a recall feed
    /// covers far more brands than PaperTrail's curated support directory.
    nonisolated static func brandMatches(_ record: RecordSnapshot, notice: RecallNotice) -> Bool {
        let noticeBrand = SupportContactDirectory.normalize(notice.brand)
        guard !noticeBrand.isEmpty else { return false }

        var candidates: [String] = []
        if let merchantName = record.merchantName, !merchantName.isEmpty {
            candidates.append(merchantName)
        }
        let tokens = record.productName
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(3)
        candidates.append(contentsOf: tokens.map(String.init))

        for candidate in candidates {
            let key = SupportContactDirectory.normalize(candidate)
            guard !key.isEmpty else { continue }
            if key == noticeBrand { return true }
            // Prefix match in either direction, same minimum-length guard
            // `SupportContactDirectory.match` uses, so a short token like
            // "Le" can't accidentally collide with an unrelated brand.
            if key.hasPrefix(noticeBrand) { return true }
            if key.count >= 4 && noticeBrand.hasPrefix(key) { return true }
        }
        return false
    }

    /// Model match: any of `notice.modelPatterns`, normalized to uppercase
    /// alphanumeric, is a prefix of or contained in the record's normalized
    /// serial number or product name. An empty `modelPatterns` means the
    /// notice applies to every product from the brand (a brand-wide recall).
    nonisolated static func modelMatches(_ record: RecordSnapshot, notice: RecallNotice) -> Bool {
        guard !notice.modelPatterns.isEmpty else { return true }

        // Minimum length 3, not just non-empty: a 1-2 char haystack (e.g. a
        // serial number field that's literally "V1") is too short to trust
        // against `pattern.hasPrefix(haystack)` below — "V11".hasPrefix("V1")
        // is true, which would falsely match a "V1" record against a "V11"
        // recall. Same rationale as `brandMatches`'s `key.count >= 4` guard.
        let haystacks = [record.serialNumber, record.productName]
            .compactMap { $0 }
            .map(normalizeModel)
            .filter { $0.count >= 3 }
        guard !haystacks.isEmpty else { return false }

        for rawPattern in notice.modelPatterns {
            let pattern = normalizeModel(rawPattern)
            guard !pattern.isEmpty else { continue }
            for haystack in haystacks {
                if haystack.contains(pattern) || pattern.hasPrefix(haystack) {
                    return true
                }
            }
        }
        return false
    }

    private nonisolated static func normalizeModel(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
