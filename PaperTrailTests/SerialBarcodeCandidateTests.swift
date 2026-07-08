import Testing
import Foundation
@testable import PaperTrail

/// Unit coverage for `SerialCandidateFilter` — the pure, Vision-independent
/// filter that decides whether a decoded barcode payload looks like a device
/// serial number. Barcode detection itself (`BarcodeDetectionService`) is
/// device/simulator-camera-dependent and can't run reliably in CI, so this
/// keeps the classification logic (the part that actually has bugs) testable.
struct SerialBarcodeCandidateTests {

    // MARK: - Accepts serial-shaped payloads

    @Test func acceptsHyphenatedSerial() {
        #expect(SerialCandidateFilter.classify("SN-9XK42") == .serial)
    }

    @Test func acceptsAppleStyleSerial() {
        #expect(SerialCandidateFilter.classify("C02XK1ABJGH5") == .serial)
    }

    // MARK: - Rejects non-serial payloads

    @Test func rejectsURLs() {
        #expect(SerialCandidateFilter.classify("https://example.com/product/123456") == nil)
        #expect(SerialCandidateFilter.classify("http://example.com") == nil)
        #expect(SerialCandidateFilter.classify("www.example.com/abc123") == nil)
    }

    @Test func rejectsShortNumericCodes() {
        // Too short to be a real serial or a UPC/EAN product code.
        #expect(SerialCandidateFilter.classify("1234") == nil)
    }

    @Test func rejectsWhitespaceJunk() {
        #expect(SerialCandidateFilter.classify("   ") == nil)
        #expect(SerialCandidateFilter.classify("AB 12 CD 34") == nil)
        #expect(SerialCandidateFilter.classify("\t\n") == nil)
    }

    @Test func rejectsPayloadsOutsideLengthBounds() {
        #expect(SerialCandidateFilter.classify("AB1") == nil) // too short (3 chars)
        #expect(SerialCandidateFilter.classify(String(repeating: "A1", count: 20)) == nil) // too long (40 chars)
    }

    @Test func rejectsDisallowedPunctuation() {
        #expect(SerialCandidateFilter.classify("SN/9XK42/AB") == nil)
        #expect(SerialCandidateFilter.classify("SN:9XK42:AB") == nil)
    }

    @Test func rejectsNumericJunkWithNoLetters() {
        // All-digit-and-hyphen but not long enough to be a UPC/EAN and no
        // letters to look like a serial.
        #expect(SerialCandidateFilter.classify("12-34-56") == nil)
    }

    // MARK: - Product codes: kept, but labeled distinctly from serials

    @Test func labelsPureUPCA12DigitAsProductCode() {
        let result = SerialCandidateFilter.classify("012345678905")
        #expect(result == .productCode)
        #expect(result != .serial)
    }

    @Test func labelsEAN13AsProductCode() {
        let result = SerialCandidateFilter.classify("4006381333931")
        #expect(result == .productCode)
    }

    @Test func rejectsShortNumericBelowProductCodeThreshold() {
        // 8-digit EAN-8-length numeric payload — below this app's product-code
        // floor, so it's rejected rather than mislabeled a product code.
        #expect(SerialCandidateFilter.classify("12345678") == nil)
    }

    // MARK: - Best-candidate selection

    @Test func bestCandidatePrefersSerialOverProductCode() {
        let best = SerialCandidateFilter.bestCandidate(from: ["012345678905", "C02XK1ABJGH5"])
        #expect(best?.kind == .serial)
        #expect(best?.payload == "C02XK1ABJGH5")
    }

    @Test func bestCandidateFallsBackToProductCodeWhenNoSerialFound() {
        let best = SerialCandidateFilter.bestCandidate(from: ["https://example.com", "012345678905"])
        #expect(best?.kind == .productCode)
        #expect(best?.payload == "012345678905")
    }

    @Test func bestCandidateReturnsNilWhenNothingQualifies() {
        #expect(SerialCandidateFilter.bestCandidate(from: ["https://example.com", "1234", "  "]) == nil)
    }

    @Test func bestCandidateReturnsNilForEmptyInput() {
        #expect(SerialCandidateFilter.bestCandidate(from: []) == nil)
    }
}
