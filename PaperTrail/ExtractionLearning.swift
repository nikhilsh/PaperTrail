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
                productHint: profile.productHint
            )
        }

        return nil
    }

    func captureFeedback(_ payload: LearningFeedbackPayload) {
        guard !payload.finalMerchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let normalized = Self.normalizeMerchantName(payload.finalMerchantName)
        guard !normalized.isEmpty else { return }

        let profile = findProfile(matchingNormalized: normalized) ?? MerchantProfile(
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
    }

    private func findProfile(matching merchantName: String) -> MerchantProfile? {
        let normalized = Self.normalizeMerchantName(merchantName)
        guard !normalized.isEmpty else { return nil }
        return findProfile(matchingNormalized: normalized)
    }

    private func findProfile(matchingNormalized normalized: String) -> MerchantProfile? {
        let descriptor = FetchDescriptor<MerchantProfile>()
        guard let profiles = try? modelContext.fetch(descriptor) else { return nil }
        return profiles.first { profile in
            if profile.normalizedName == normalized { return true }
            return profile.aliases.contains { Self.normalizeMerchantName($0) == normalized }
        }
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
}
