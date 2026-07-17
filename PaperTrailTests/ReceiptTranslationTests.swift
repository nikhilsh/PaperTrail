import Testing
import Foundation
@testable import PaperTrail

/// Pure-logic coverage for receipt translation (`Flag.translate`):
/// - the "should we offer translation" decision, across detected language ×
///   user language × Translation-framework availability
/// - the line split/rejoin round trip receipts are translated through
///
/// Actual on-device translation (`TranslationSession`, language pack
/// download) cannot run in CI — see `ReceiptTranslationView.swift`'s
/// "NEEDS ON-DEVICE VERIFICATION" note.
struct ReceiptTranslationTests {

    // MARK: - shouldOffer: happy path

    @Test func offersWhenDetectedDiffersAndSupported() {
        #expect(ReceiptTranslationOffer.shouldOffer(
            detectedLanguageCode: "ja",
            confidence: 0.9,
            targetLanguageCode: "en",
            availability: .supported
        ) == true)
    }

    @Test func offersWhenAlreadyInstalled() {
        #expect(ReceiptTranslationOffer.shouldOffer(
            detectedLanguageCode: "ja",
            confidence: 0.75,
            targetLanguageCode: "en",
            availability: .installed
        ) == true)
    }

    // MARK: - shouldOffer: negative cases

    @Test func doesNotOfferWhenNoLanguageDetected() {
        #expect(ReceiptTranslationOffer.shouldOffer(
            detectedLanguageCode: nil,
            confidence: 0.9,
            targetLanguageCode: "en",
            availability: .supported
        ) == false)
    }

    @Test func doesNotOfferWhenConfidenceTooLow() {
        #expect(ReceiptTranslationOffer.shouldOffer(
            detectedLanguageCode: "ja",
            confidence: 0.2,
            targetLanguageCode: "en",
            availability: .supported
        ) == false)
    }

    @Test func doesNotOfferAtExactConfidenceFloor() {
        // The floor itself is inclusive — this documents the boundary.
        #expect(ReceiptTranslationOffer.shouldOffer(
            detectedLanguageCode: "ja",
            confidence: ReceiptTranslationOffer.minimumConfidence,
            targetLanguageCode: "en",
            availability: .supported
        ) == true)
        #expect(ReceiptTranslationOffer.shouldOffer(
            detectedLanguageCode: "ja",
            confidence: ReceiptTranslationOffer.minimumConfidence - 0.01,
            targetLanguageCode: "en",
            availability: .supported
        ) == false)
    }

    @Test func doesNotOfferWhenDetectedMatchesTarget() {
        #expect(ReceiptTranslationOffer.shouldOffer(
            detectedLanguageCode: "en",
            confidence: 0.95,
            targetLanguageCode: "en",
            availability: .supported
        ) == false)
    }

    @Test func doesNotOfferWhenLanguagesMatchByRegionOnly() {
        // "en-US" detected vs plain "en" preferred — same language, different
        // region specificity; must not offer to translate English to English.
        #expect(ReceiptTranslationOffer.shouldOffer(
            detectedLanguageCode: "en-US",
            confidence: 0.95,
            targetLanguageCode: "en",
            availability: .supported
        ) == false)
    }

    @Test func doesNotOfferWhenPairingUnsupported() {
        #expect(ReceiptTranslationOffer.shouldOffer(
            detectedLanguageCode: "ja",
            confidence: 0.95,
            targetLanguageCode: "en",
            availability: .unsupported
        ) == false)
    }

    // MARK: - languageCodesMatch

    @Test func languageCodesMatchIgnoresRegionAndCase() {
        #expect(ReceiptTranslationOffer.languageCodesMatch("en", "en") == true)
        #expect(ReceiptTranslationOffer.languageCodesMatch("en-US", "en-GB") == true)
        #expect(ReceiptTranslationOffer.languageCodesMatch("EN", "en") == true)
        #expect(ReceiptTranslationOffer.languageCodesMatch("ja", "en") == false)
    }

    // MARK: - Line split/rejoin round trip

    @Test func splitLinesDropsBlankLinesAndTrimsWhitespace() {
        let text = "SUPER MART\n  123 Main St  \n\nTotal: ¥3,200\n"
        #expect(ReceiptLineTranslation.splitLines(text) == ["SUPER MART", "123 Main St", "Total: ¥3,200"])
    }

    @Test func splitThenJoinRoundTripsForCleanInput() {
        let lines = ["スーパーマート", "合計: ¥3,200", "ありがとうございました"]
        let text = lines.joined(separator: "\n")
        #expect(ReceiptLineTranslation.splitLines(text) == lines)
        #expect(ReceiptLineTranslation.joinLines(ReceiptLineTranslation.splitLines(text)) == text)
    }

    @Test func splitLinesOfEmptyTextIsEmpty() {
        #expect(ReceiptLineTranslation.splitLines("").isEmpty)
        #expect(ReceiptLineTranslation.splitLines("   \n\n  ").isEmpty)
    }

    @Test func joinLinesOfEmptyArrayIsEmptyString() {
        #expect(ReceiptLineTranslation.joinLines([]) == "")
    }

    // MARK: - In-memory cache

    @Test func cacheRoundTripsPerAttachmentAndLanguage() {
        ReceiptTranslationCache.removeAll()
        let id = UUID()
        #expect(ReceiptTranslationCache.get(attachmentID: id, targetLanguageCode: "en") == nil)

        ReceiptTranslationCache.set("Total: $32.00", attachmentID: id, targetLanguageCode: "en")
        #expect(ReceiptTranslationCache.get(attachmentID: id, targetLanguageCode: "en") == "Total: $32.00")

        // A different target language for the same attachment is a distinct
        // cache entry.
        #expect(ReceiptTranslationCache.get(attachmentID: id, targetLanguageCode: "fr") == nil)

        ReceiptTranslationCache.removeAll()
        #expect(ReceiptTranslationCache.get(attachmentID: id, targetLanguageCode: "en") == nil)
    }
}
