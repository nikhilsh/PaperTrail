import Foundation
import OSLog

/// On-device, embedding-based category suggestion.
///
/// When neither the Foundation Model nor the learning loop produced a category,
/// this maps a product name to the nearest of our fixed categories by semantic
/// similarity against a small set of exemplar phrases — so it generalizes to
/// products we've never seen ("Nespresso Vertuo" → Kitchen) without any model
/// download or training. Fully offline via `SemanticMatcher` (`NLEmbedding`).
///
/// Categories mirror the Foundation Model's `@Guide` enum so suggestions are
/// always one of the values the rest of the app expects.
enum CategoryClassifier {

    private static let logger = Logger(subsystem: "nikhilsh.PaperTrail", category: "extraction.category")

    /// Category → exemplar product phrases. Exemplars are deliberately concrete;
    /// embeddings cluster a query near whichever set it most resembles.
    static let exemplars: [String: [String]] = [
        "Electronics": ["laptop computer", "smartphone", "wireless headphones", "television", "digital camera", "tablet", "computer monitor", "bluetooth speaker", "wifi router", "game console"],
        "Appliance": ["refrigerator", "washing machine", "vacuum cleaner", "air conditioner", "microwave oven", "dishwasher", "clothes dryer", "water heater"],
        "Kitchen": ["blender", "coffee machine", "cookware pot", "knife set", "toaster", "air fryer", "electric kettle", "rice cooker"],
        "Furniture": ["sofa couch", "dining table", "office chair", "bed frame", "bookshelf", "wardrobe cabinet", "study desk"],
        "Clothing": ["shirt", "sneakers shoes", "winter jacket", "dress", "trousers", "wristwatch", "handbag", "sunglasses"],
        "Sports": ["bicycle", "treadmill", "dumbbell weights", "tennis racket", "yoga mat", "running shoes", "golf clubs"],
        "Health": ["massage chair", "blood pressure monitor", "thermometer", "vitamins supplements", "electric toothbrush", "fitness tracker"],
        "Home": ["table lamp lighting", "curtains", "bedsheets linen", "air purifier", "electric fan", "storage box"],
    ]

    /// Exemplar phrases pre-embedded once. The exemplar set is constant, so its
    /// vectors never change — caching them means a scan embeds only the query
    /// (once), not all ~60 exemplars on every call.
    private static let exemplarVectors: [(category: String, vector: [Double])] = {
        var result: [(String, [Double])] = []
        for (category, phrases) in exemplars {
            for phrase in phrases {
                if let v = SemanticMatcher.shared.vector(for: phrase) {
                    result.append((category, v))
                }
            }
        }
        return result
    }()

    /// Deterministic word → category table, checked before any fuzzy matching.
    /// Embeddings mislead on brand-y compound names ("Rheem STORAGE Heater"
    /// drifts toward Home's "storage box"); an unambiguous keyword is
    /// near-certain for this taxonomy, so it wins over both the embedding
    /// fallback and a fuzzy model guess.
    static let categoryKeywords: [String: [String]] = [
        "Appliance": ["heater", "geyser", "boiler", "fridge", "refriger", "freezer",
                      "washer", "washing machine", "dryer", "dishwasher", "microwave",
                      "oven", "hob", "cooktop", "stove", "aircon", "air condition", "vacuum"],
        "Electronics": ["laptop", "macbook", "iphone", "smartphone", "tablet", "ipad",
                        "televis", " tv", "tv ", "monitor", "camera", "console", "router",
                        "speaker", "soundbar", "headphone", "earbud"],
        "Kitchen": ["kettle", "blender", "toaster", "air fryer", "airfryer",
                    "rice cooker", "coffee", "espresso"],
        "Furniture": ["sofa", "couch", "chair", "desk", "table", "mattress",
                      "wardrobe", "bookshelf"],
        "Sports": ["bicycle", "treadmill", "dumbbell", "racket", "yoga"],
        "Clothing": ["shirt", "jacket", "sneaker", "shoes", "trousers", "handbag"],
        "Home": ["lamp", "curtain", "bedsheet", "linen"],
    ]

    /// The category whose keyword list matches `text` — but only when exactly
    /// one category matches. "Coffee table" hits Kitchen AND Furniture →
    /// ambiguous → nil, and the embedding path decides instead.
    static func keywordCategory(_ text: String) -> String? {
        let hay = " " + text.lowercased() + " "
        var matched: String?
        for (category, words) in categoryKeywords {
            guard words.contains(where: { hay.contains($0) }) else { continue }
            if matched != nil { return nil }
            matched = category
        }
        return matched
    }

    /// Suggest a category for a product/description, or `nil` if no exemplar set
    /// is similar enough (or embeddings are unavailable).
    ///
    /// - Parameter minSimilarity: floor for the best match. ~0.5 keeps confident
    ///   suggestions while avoiding random assignment for unrelated text.
    static func classify(_ text: String, minSimilarity: Double = 0.5) -> String? {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3,
              let queryVector = SemanticMatcher.shared.vector(for: query),
              !exemplarVectors.isEmpty else { return nil }

        var best: (category: String, score: Double)?
        for (category, vector) in exemplarVectors {
            guard let score = SemanticMatcher.shared.cosineSimilarity(queryVector, vector) else { continue }
            if best == nil || score > best!.score {
                best = (category, score)
            }
        }

        guard let best, best.score >= minSimilarity else { return nil }
        logger.info("Category suggestion: score=\(best.score, privacy: .public)")
        return best.category
    }
}
