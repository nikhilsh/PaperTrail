import Foundation
import SwiftData

@Model
final class MerchantProfile {
    var id: UUID = UUID()
    var normalizedName: String = ""
    var displayName: String = ""
    var aliasesRaw: String = ""
    var defaultCategory: String?
    var defaultCurrency: String?
    var commonWarrantyMonths: Int?
    var documentKindsRaw: String = ""
    var amountHint: String?
    var dateHint: String?
    var productHint: String?
    var notes: String?
    var correctionCount: Int = 0
    var lastUsedAt: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        normalizedName: String,
        displayName: String,
        aliases: [String] = [],
        defaultCategory: String? = nil,
        defaultCurrency: String? = nil,
        commonWarrantyMonths: Int? = nil,
        documentKinds: [DocumentKind] = [],
        amountHint: String? = nil,
        dateHint: String? = nil,
        productHint: String? = nil,
        notes: String? = nil,
        correctionCount: Int = 0,
        lastUsedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.normalizedName = normalizedName
        self.displayName = displayName
        self.aliasesRaw = aliases.joined(separator: "||")
        self.defaultCategory = defaultCategory
        self.defaultCurrency = defaultCurrency
        self.commonWarrantyMonths = commonWarrantyMonths
        self.documentKindsRaw = documentKinds.map(\.rawValue).joined(separator: ",")
        self.amountHint = amountHint
        self.dateHint = dateHint
        self.productHint = productHint
        self.notes = notes
        self.correctionCount = correctionCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension MerchantProfile {
    var aliases: [String] {
        get {
            aliasesRaw.split(separator: "|")
                .map(String.init)
                .joined(separator: "|")
                .split(separator: "||")
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            aliasesRaw = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "||")
        }
    }

    var documentKinds: [DocumentKind] {
        get {
            documentKindsRaw
                .split(separator: ",")
                .compactMap { DocumentKind(rawValue: String($0)) }
        }
        set {
            documentKindsRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    /// Trust score for this profile's hints, in `[0, 1]`.
    ///
    /// Combines two signals:
    ///   • **correction count** — a merchant corrected many times is more
    ///     authoritative (saturates at ~10 corrections),
    ///   • **recency** — exponential decay (~6-month time constant) so stale
    ///     profiles fade rather than mislead after a store changes its layout.
    var hintStrength: Double {
        let countFactor = min(1.0, Double(max(0, correctionCount)) / 10.0)
        let days = max(0.0, Date.now.timeIntervalSince(lastUsedAt) / 86_400.0)
        let recency = exp(-days / 180.0)
        // Weight evidence (count) more than recency, but let staleness pull it down.
        return min(1.0, countFactor * 0.7 + recency * 0.3)
    }
}

struct MerchantLearningContext: Sendable {
    let profileID: UUID?
    let normalizedMerchantName: String?
    let displayMerchantName: String?
    let categorySuggestion: String?
    let currencySuggestion: String?
    let warrantySuggestionMonths: Int?
    let amountHint: String?
    let dateHint: String?
    let productHint: String?

    /// How much to trust this profile's hints, in `[0, 1]`. Derived from the
    /// number of corrections (a merchant corrected 10× is near-authoritative)
    /// decayed by recency (stores change layout; old corrections weigh less).
    /// Consumers phrase the model prompt more or less forcefully and decide
    /// whether to auto-apply suggestions. See `MerchantProfile.hintStrength`.
    var confidence: Double = 0

    /// Whether the hints are strong enough to auto-apply without the user asking.
    var isAuthoritative: Bool { confidence >= 0.6 }
}

// MARK: - Item-level category memory

/// Learns `product → category` independent of where it was bought, so "AirPods"
/// maps to Electronics whether purchased at the Apple Store or a corner shop.
/// Complements `MerchantProfile` (which learns `merchant → category`).
@Model
final class ProductCategoryMemory {
    var id: UUID = UUID()
    var normalizedProduct: String = ""
    var displayProduct: String = ""
    var category: String = ""
    var count: Int = 0
    var lastUsedAt: Date = Date()
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        normalizedProduct: String,
        displayProduct: String,
        category: String,
        count: Int = 1,
        lastUsedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.normalizedProduct = normalizedProduct
        self.displayProduct = displayProduct
        self.category = category
        self.count = count
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
    }
}

struct LearningFeedbackPayload: Sendable {
    let structured: StructuredExtractionResult?
    let documentKind: DocumentKind?
    let finalProductName: String
    let finalMerchantName: String
    let finalPurchaseDate: Date
    let finalAmount: Double?
    let finalCurrency: String
    let finalCategory: String
    let finalWarrantyMonths: Int?
}

@MainActor
struct MerchantLearningService {
    let modelContext: ModelContext

    func learningContext(for structured: StructuredExtractionResult?) -> MerchantLearningContext? {
        guard let structured else { return nil }

        let merchantCandidates = [
            structured.merchantName.value,
            structured.productName.value
        ].compactMap { $0 }

        for candidate in merchantCandidates {
            guard let profile = findProfile(matching: candidate) else { continue }
            profile.lastUsedAt = .now
            profile.updatedAt = .now
            return MerchantLearningContext(
                profileID: profile.id,
                normalizedMerchantName: profile.normalizedName,
                displayMerchantName: profile.displayName,
                categorySuggestion: profile.defaultCategory,
                currencySuggestion: profile.defaultCurrency,
                warrantySuggestionMonths: profile.commonWarrantyMonths,
                amountHint: profile.amountHint,
                dateHint: profile.dateHint,
                productHint: profile.productHint,
                confidence: profile.hintStrength
            )
        }

        return nil
    }

    func captureFeedback(_ payload: LearningFeedbackPayload) {
        // Emit per-field correction metrics first — these matter even when the
        // merchant name is blank (we still learn how often each field is edited).
        emitCorrectionMetrics(payload)

        guard !payload.finalMerchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let normalized = Self.normalizeMerchantName(payload.finalMerchantName)
        guard !normalized.isEmpty else { return }

        // Use fuzzy matching so OCR variants of the same store ("Harvey Norman"
        // vs "HARVEY NORMAN (Suntec)") aggregate into one profile instead of
        // fragmenting the learning loop.
        let profile = findProfile(matching: payload.finalMerchantName) ?? MerchantProfile(
            normalizedName: normalized,
            displayName: payload.finalMerchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if profile.modelContext == nil {
            modelContext.insert(profile)
        }

        profile.displayName = payload.finalMerchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.lastUsedAt = .now
        profile.updatedAt = .now
        profile.correctionCount += 1

        var aliases = Set(profile.aliases)
        if let extractedMerchant = payload.structured?.merchantName.value,
           !extractedMerchant.isEmpty,
           extractedMerchant.caseInsensitiveCompare(profile.displayName) != .orderedSame {
            aliases.insert(extractedMerchant)
        }
        aliases.insert(profile.displayName)
        profile.aliases = Array(aliases).sorted()

        if !payload.finalCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.defaultCategory = payload.finalCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !payload.finalCurrency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.defaultCurrency = payload.finalCurrency.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let months = payload.finalWarrantyMonths, months > 0 {
            profile.commonWarrantyMonths = months
        }

        let resolvedKind = payload.documentKind ?? payload.structured?.documentKind.value
        if let resolvedKind {
            var kinds = profile.documentKinds
            if !kinds.contains(resolvedKind) {
                kinds.append(resolvedKind)
                profile.documentKinds = kinds
            }
        }

        profile.amountHint = inferAmountHint(from: payload)
        profile.dateHint = inferDateHint(from: payload.finalPurchaseDate)
        profile.productHint = inferProductHint(from: payload.finalProductName)
        profile.notes = buildNotes(from: payload)

        // Item-level learning: remember product → category independent of merchant.
        let category = payload.finalCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !category.isEmpty {
            recordProductCategory(product: payload.finalProductName, category: category)
            for item in payload.structured?.lineItems ?? [] where item.kind.isRecordWorthy {
                recordProductCategory(product: item.name, category: category)
            }
        }
    }

    /// Similarity threshold for treating two merchant strings as the same store.
    /// Sentence embeddings score near-duplicates very high; 0.82 avoids merging
    /// genuinely different merchants while catching OCR/casing variants.
    private static let fuzzyMerchantThreshold = 0.82

    /// Similarity threshold for matching an unseen product to a learned one.
    private static let fuzzyProductThreshold = 0.85

    private func findProfile(matching merchantName: String) -> MerchantProfile? {
        let normalized = Self.normalizeMerchantName(merchantName)
        guard !normalized.isEmpty else { return nil }
        if let exact = findProfile(matchingNormalized: normalized) { return exact }
        return findProfileFuzzy(matching: merchantName)
    }

    private func findProfile(matchingNormalized normalized: String) -> MerchantProfile? {
        let descriptor = FetchDescriptor<MerchantProfile>()
        guard let profiles = try? modelContext.fetch(descriptor) else { return nil }
        return profiles.first { profile in
            if profile.normalizedName == normalized { return true }
            return profile.aliases.contains { Self.normalizeMerchantName($0) == normalized }
        }
    }

    /// Embedding-based fallback: match by *meaning* when exact normalization
    /// misses. Returns the most similar profile above the threshold, if any.
    private func findProfileFuzzy(matching merchantName: String) -> MerchantProfile? {
        let query = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3, SemanticMatcher.shared.isAvailable else { return nil }

        let descriptor = FetchDescriptor<MerchantProfile>()
        guard let profiles = try? modelContext.fetch(descriptor), !profiles.isEmpty else { return nil }

        var best: (profile: MerchantProfile, score: Double)?
        for profile in profiles {
            let candidates = [profile.displayName] + profile.aliases
            for candidate in candidates {
                guard let score = SemanticMatcher.shared.similarity(query, candidate) else { continue }
                if score >= Self.fuzzyMerchantThreshold, best == nil || score > best!.score {
                    best = (profile, score)
                }
            }
        }
        return best?.profile
    }

    // MARK: - Item-level product → category

    /// Upsert a learned `product → category` association.
    private func recordProductCategory(product: String, category: String) {
        let normalized = Self.normalizeProductName(product)
        guard normalized.count >= 3 else { return }

        let descriptor = FetchDescriptor<ProductCategoryMemory>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        if let memory = existing.first(where: { $0.normalizedProduct == normalized }) {
            if memory.category.caseInsensitiveCompare(category) == .orderedSame {
                memory.count += 1
            } else {
                // Category changed — latest correction wins, evidence resets.
                memory.category = category
                memory.count = 1
            }
            memory.displayProduct = product.trimmingCharacters(in: .whitespacesAndNewlines)
            memory.lastUsedAt = .now
        } else {
            modelContext.insert(ProductCategoryMemory(
                normalizedProduct: normalized,
                displayProduct: product.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category
            ))
        }
    }

    /// Suggest a category for a product from item-level memory. Tries an exact
    /// normalized-token match first, then an embedding fuzzy match.
    func productCategorySuggestion(for product: String) -> String? {
        let normalized = Self.normalizeProductName(product)
        guard normalized.count >= 3 else { return nil }

        let descriptor = FetchDescriptor<ProductCategoryMemory>()
        guard let memories = try? modelContext.fetch(descriptor), !memories.isEmpty else { return nil }

        if let exact = memories.first(where: { $0.normalizedProduct == normalized }) {
            return exact.category
        }

        guard SemanticMatcher.shared.isAvailable else { return nil }
        let query = product.trimmingCharacters(in: .whitespacesAndNewlines)
        var best: (category: String, score: Double)?
        for memory in memories {
            guard let score = SemanticMatcher.shared.similarity(query, memory.displayProduct) else { continue }
            if score >= Self.fuzzyProductThreshold, best == nil || score > best!.score {
                best = (memory.category, score)
            }
        }
        return best?.category
    }

    /// All learned merchant display names — used to seed OCR `customWords`.
    func learnedMerchantNames() -> [String] {
        let descriptor = FetchDescriptor<MerchantProfile>()
        guard let profiles = try? modelContext.fetch(descriptor) else { return [] }
        return profiles.map(\.displayName).filter { $0.count >= 2 }
    }

    private func inferAmountHint(from payload: LearningFeedbackPayload) -> String? {
        guard let finalAmount = payload.finalAmount else { return nil }
        if let extracted = payload.structured?.amount.value {
            if finalAmount > extracted + 0.01 {
                return "Prefer the largest final total, not subtotal or tax-exclusive amounts."
            }
            if finalAmount + 0.01 < extracted {
                return "Check for discounts, deposits, or line-item amounts before choosing total."
            }
        }
        return payload.structured?.lineItems.isEmpty == false
            ? "Look near the grand total / amount due region and compare against line items."
            : nil
    }

    private func inferDateHint(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = Locale(identifier: "en_SG")
        return "This merchant commonly uses purchase dates like \(formatter.string(from: date)) in day-first format."
    }

    private func inferProductHint(from productName: String) -> String? {
        let trimmed = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "Prefer the main purchased item line similar to '\(trimmed)'."
    }

    private func buildNotes(from payload: LearningFeedbackPayload) -> String? {
        var bits: [String] = []
        if let kind = payload.documentKind ?? payload.structured?.documentKind.value {
            bits.append("Usually appears as a \(kind.label.lowercased())")
        }
        if let source = payload.structured?.source {
            bits.append("Learned from \(source.rawValue) correction")
        }
        return bits.isEmpty ? nil : bits.joined(separator: ". ")
    }

    static func normalizeMerchantName(_ name: String) -> String {
        let lowered = name.lowercased()
        let allowed = lowered.map { char -> Character in
            if char.isLetter || char.isNumber || char.isWhitespace {
                return char
            }
            return " "
        }
        let collapsed = String(allowed)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let stopwords: Set<String> = ["pte", "ltd", "sdn", "bhd", "inc", "llc", "company", "co", "store", "the"]
        let filtered = collapsed
            .split(separator: " ")
            .map(String.init)
            .filter { !stopwords.contains($0) }
            .joined(separator: " ")

        return filtered.isEmpty ? collapsed : filtered
    }

    /// Normalize a product name for item-level memory keys: lowercased,
    /// alphanumerics only, collapsed whitespace. Keeps model numbers intact.
    static func normalizeProductName(_ name: String) -> String {
        let lowered = name.lowercased()
        let allowed = lowered.map { char -> Character in
            (char.isLetter || char.isNumber || char.isWhitespace) ? char : " "
        }
        return String(allowed)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Correction metrics

    /// Compare what extraction suggested against what the user saved, and emit
    /// per-field correction outcomes (privacy-safe: field names + outcomes only).
    private func emitCorrectionMetrics(_ payload: LearningFeedbackPayload) {
        let sr = payload.structured
        var outcomes: [String: ExtractionMetrics.FieldOutcome] = [:]

        func outcome(extracted: String?, final: String) -> ExtractionMetrics.FieldOutcome {
            let e = extracted?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let f = final.trimmingCharacters(in: .whitespacesAndNewlines)
            if e.isEmpty { return f.isEmpty ? .empty : .filledBlank }
            return e.caseInsensitiveCompare(f) == .orderedSame ? .kept : .corrected
        }

        outcomes["product"] = outcome(extracted: sr?.productName.value, final: payload.finalProductName)
        outcomes["merchant"] = outcome(extracted: sr?.merchantName.value, final: payload.finalMerchantName)
        outcomes["currency"] = outcome(extracted: sr?.currency.value, final: payload.finalCurrency)
        outcomes["category"] = outcome(extracted: sr?.category.value, final: payload.finalCategory)

        // Amount: numeric comparison with a cent of tolerance.
        outcomes["amount"] = {
            guard let final = payload.finalAmount else {
                return sr?.amount.value == nil ? .empty : .corrected
            }
            guard let extracted = sr?.amount.value else { return .filledBlank }
            return abs(extracted - final) < 0.01 ? .kept : .corrected
        }()

        ExtractionMetrics.recordCorrectionOutcomes(outcomes, source: sr?.source)
    }
}
