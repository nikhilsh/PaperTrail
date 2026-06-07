import Foundation
import NaturalLanguage
import OSLog

/// On-device semantic similarity via Apple's Natural Language framework.
///
/// Wraps `NLEmbedding` sentence embeddings so two short strings can be compared
/// by *meaning* rather than exact characters — fully offline, nothing leaves the
/// device. Two consumers:
///   • **Fuzzy merchant matching** — collapse OCR variants of one store
///     ("Harvey Norman" vs "HARVEY NORMAN (Suntec)") into one `MerchantProfile`.
///   • **Category suggestion** — map an unseen product name to the nearest
///     category exemplar.
///
/// The embedding asset may be absent (older devices, unsupported locale); every
/// method degrades to `nil`/`false` so callers fall back to exact matching.
///
/// `@unchecked Sendable`: `NLEmbedding` is a reference type that isn't formally
/// `Sendable`, but it is immutable after construction here and its read APIs
/// (`distance`, `vector`) are safe to call concurrently.
final class SemanticMatcher: @unchecked Sendable {

    static let shared = SemanticMatcher()

    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "extraction.semantic")

    private let embedding: NLEmbedding?

    private init() {
        embedding = NLEmbedding.sentenceEmbedding(for: .english)
        if embedding == nil {
            Self.logger.info("Sentence embedding unavailable — semantic matching disabled, falling back to exact match")
        }
    }

    /// Whether semantic matching is available on this device.
    var isAvailable: Bool { embedding != nil }

    /// Cosine *similarity* in `[0, 1]` (1 = identical meaning), or `nil` if
    /// embeddings are unavailable or undefined for the inputs.
    func similarity(_ a: String, _ b: String) -> Double? {
        guard let embedding else { return nil }
        let lhs = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = b.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lhs.isEmpty, !rhs.isEmpty else { return nil }

        // NLEmbedding cosine distance is in [0, 2]; map to similarity in [0, 1].
        let distance = embedding.distance(between: lhs, and: rhs, distanceType: .cosine)
        guard distance.isFinite else { return nil }
        return max(0.0, min(1.0, 1.0 - distance / 2.0))
    }

    /// Raw sentence-embedding vector for `text`, or `nil` if embeddings are
    /// unavailable or undefined for the input. Use with `cosineSimilarity` to
    /// embed a query once and compare it against many pre-embedded candidates,
    /// instead of re-embedding both strings on every `similarity` call.
    func vector(for text: String) -> [Double]? {
        guard let embedding else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let v = embedding.vector(for: trimmed)
        return (v?.isEmpty == false) ? v : nil
    }

    /// Cosine *similarity* in `[0, 1]` between two embedding vectors, matching the
    /// scale of `similarity(_:_:)` (which maps cosine distance `1 - d/2`).
    func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return nil }
        let cosine = dot / (normA.squareRoot() * normB.squareRoot())
        guard cosine.isFinite else { return nil }
        return max(0.0, min(1.0, (cosine + 1.0) / 2.0))
    }

    /// The best match for `query` among `candidates` whose similarity meets
    /// `threshold`. Returns the candidate and its score, or `nil`.
    func bestMatch<C: Sequence>(
        for query: String,
        among candidates: C,
        threshold: Double
    ) -> (value: String, score: Double)? where C.Element == String {
        guard isAvailable else { return nil }
        var best: (value: String, score: Double)?
        for candidate in candidates {
            guard let score = similarity(query, candidate) else { continue }
            if score >= threshold, best == nil || score > best!.score {
                best = (candidate, score)
            }
        }
        return best
    }
}
