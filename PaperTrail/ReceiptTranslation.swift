import Foundation
import NaturalLanguage

// MARK: - Availability (mirrors Translation.LanguageAvailability.Status)

/// Mirrors `Translation.LanguageAvailability.Status` (`.installed` /
/// `.supported` / `.unsupported`) without importing `Translation` here, so
/// `ReceiptTranslationOffer.shouldOffer` below is a pure function the
/// simulator/CI can exercise without a device or a downloaded language pack.
/// `ReceiptTranslationPanel` (SwiftUI, uses the real `Translation` framework)
/// maps the live enum onto this one at its single call site.
enum TranslationPairingAvailability {
    case installed
    case supported
    case unsupported
}

// MARK: - Offer decision (pure, testable)

/// Decision logic for whether PaperTrail shows a "Translate from <language>"
/// affordance for a receipt's OCR text. Kept free of `NLLanguageRecognizer`
/// and `Translation` framework calls so it's covered by plain unit tests —
/// see `ReceiptTranslationTests`.
enum ReceiptTranslationOffer {
    /// Confidence floor below which `NLLanguageRecognizer`'s dominant-
    /// language guess is too shaky to act on. Mirrors
    /// `EXTRACTION_ARCHITECTURE.md`'s humility principle — a low-confidence
    /// guess should not drive a user-visible offer.
    static let minimumConfidence: Double = 0.6

    /// Should PaperTrail offer to translate this receipt?
    ///
    /// Requires all three:
    /// - (a) a dominant language was detected with confidence >= `minimumConfidence`
    /// - (b) it differs from the user's target/preferred language
    /// - (c) the Translation framework reports the pairing as `.installed` or
    ///   `.supported` (never `.unsupported`)
    static func shouldOffer(
        detectedLanguageCode: String?,
        confidence: Double,
        targetLanguageCode: String,
        availability: TranslationPairingAvailability
    ) -> Bool {
        guard let detectedLanguageCode, !detectedLanguageCode.isEmpty else { return false }
        guard confidence >= minimumConfidence else { return false }
        guard !languageCodesMatch(detectedLanguageCode, targetLanguageCode) else { return false }
        switch availability {
        case .installed, .supported: return true
        case .unsupported: return false
        }
    }

    /// Base-language comparison so "en" and "en-US" (or "ja" and "ja-JP")
    /// count as the same language — `NLLanguageRecognizer` and
    /// `Locale.current.language.languageCode` can differ in region
    /// specificity.
    static func languageCodesMatch(_ a: String, _ b: String) -> Bool {
        func normalize(_ code: String) -> String {
            code.split(separator: "-").first.map(String.init)?.lowercased() ?? code.lowercased()
        }
        return normalize(a) == normalize(b)
    }
}

// MARK: - Line split/rejoin (pure, testable)

/// Receipts are line-oriented — splitting on newlines before translating,
/// then rejoining, keeps each line's translation aligned with the batch
/// `session.translations(from:)` request order and makes the translated
/// result read the way the receipt reads.
enum ReceiptLineTranslation {
    static func splitLines(_ text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func joinLines(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }
}

// MARK: - Language detection (thin NLLanguageRecognizer wrapper)

/// Wraps `NLLanguageRecognizer` — not itself unit-testable (depends on the
/// live NL model), but kept tiny so all the decision logic it feeds lives in
/// `ReceiptTranslationOffer` above.
enum ReceiptLanguageDetector {
    struct Result: Equatable {
        let languageCode: String
        let confidence: Double
    }

    static func detectDominantLanguage(in text: String) -> Result? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        let confidence = hypotheses[language] ?? 0
        return Result(languageCode: language.rawValue, confidence: confidence)
    }
}

// MARK: - In-memory cache

/// Translated receipt text, cached in memory only — never persisted, never
/// added to `PurchaseRecord`/`Attachment` (CloudKit/SwiftData schema is
/// load-bearing, see CLAUDE.md). Keyed by attachment id (finer-grained than
/// record id — a record can carry more than one document) + target language,
/// so switching the app's language re-translates rather than showing stale
/// text.
enum ReceiptTranslationCache {
    private final class Box {
        let value: String
        init(_ value: String) { self.value = value }
    }

    private static let cache = NSCache<NSString, Box>()

    private static func key(attachmentID: UUID, targetLanguageCode: String) -> NSString {
        "\(attachmentID.uuidString)|\(targetLanguageCode)" as NSString
    }

    static func get(attachmentID: UUID, targetLanguageCode: String) -> String? {
        cache.object(forKey: key(attachmentID: attachmentID, targetLanguageCode: targetLanguageCode))?.value
    }

    static func set(_ text: String, attachmentID: UUID, targetLanguageCode: String) {
        cache.setObject(Box(text), forKey: key(attachmentID: attachmentID, targetLanguageCode: targetLanguageCode))
    }

    /// Test-only reset — the cache is a process-wide singleton, so tests
    /// that populate it must clean up after themselves.
    static func removeAll() {
        cache.removeAllObjects()
    }
}
