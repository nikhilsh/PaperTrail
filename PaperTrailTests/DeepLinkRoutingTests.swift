import Testing
import Foundation
@testable import PaperTrail

/// Pure `URL → Route` parsing tests for the `papertrail://` deep-link
/// scheme — no UIKit/SwiftData involved, so these run without a device or
/// simulator lifecycle. See `AppShellView.Route`.
struct DeepLinkRoutingTests {

    @Test func recordLinkParsesUUID() throws {
        let id = UUID()
        let url = try #require(URL(string: "papertrail://record/\(id.uuidString)"))
        #expect(Route(url: url) == .record(id))
    }

    @Test func recordLinkWithMalformedUUIDReturnsNil() throws {
        let url = try #require(URL(string: "papertrail://record/not-a-uuid"))
        #expect(Route(url: url) == nil)
    }

    @Test func recordLinkWithNoUUIDReturnsNil() throws {
        let url = try #require(URL(string: "papertrail://record/"))
        #expect(Route(url: url) == nil)
    }

    @Test func captureLinkParses() throws {
        let url = try #require(URL(string: "papertrail://capture"))
        #expect(Route(url: url) == .capture)
    }

    @Test func expiringLinkParses() throws {
        let url = try #require(URL(string: "papertrail://expiring"))
        #expect(Route(url: url) == .expiringSoon)
    }

    @Test func unknownHostReturnsNil() throws {
        let url = try #require(URL(string: "papertrail://somethingElse"))
        #expect(Route(url: url) == nil)
    }

    @Test func wrongSchemeReturnsNil() throws {
        let url = try #require(URL(string: "https://papertrail.kaopeh.com/record/\(UUID().uuidString)"))
        #expect(Route(url: url) == nil)
    }
}

/// `SpotlightIndexer`'s pure text-truncation helper — UIKit/CoreSpotlight-free.
struct SpotlightIndexerTruncationTests {

    @Test func shortTextIsUnchanged() {
        let text = "Sony WH-1000XM5 — Best Buy receipt"
        #expect(SpotlightIndexer.truncated(text, maxBytes: 4096) == text)
    }

    @Test func longTextIsTruncatedWithinByteBudget() {
        let text = String(repeating: "a", count: 5000)
        let result = SpotlightIndexer.truncated(text, maxBytes: 4096)
        #expect(result.utf8.count <= 4096)
        #expect(result.utf8.count > 0)
    }

    @Test func truncationNeverSplitsAMultiByteCharacter() {
        // Every character is a 3-byte UTF-8 emoji-adjacent symbol; a byte-level
        // (rather than Character-level) truncation would produce invalid UTF-8
        // or a dropped/garbled trailing character.
        let text = String(repeating: "€", count: 2000) // '€' is 3 bytes in UTF-8
        let result = SpotlightIndexer.truncated(text, maxBytes: 100)
        #expect(result.utf8.count <= 100)
        // Round-trips cleanly through UTF-8 decoding with no corruption.
        #expect(String(decoding: Array(result.utf8), as: UTF8.self) == result)
    }
}
