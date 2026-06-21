import Testing
import Foundation
import SwiftData
@testable import PaperTrail

/// Item-level learning: ProductCategoryMemory now carries a hintStrength
/// (evidence × recency, mirroring MerchantProfile) and the category suggester
/// gates on it — a one-off memory from a year ago fades instead of mislabeling
/// forever.
struct ProductMemoryLearningTests {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([PurchaseRecord.self, Attachment.self, MerchantProfile.self, ProductCategoryMemory.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @Test func productHintStrengthRewardsEvidenceAndFreshness() {
        let freshStrong = ProductCategoryMemory(
            normalizedProduct: "espresso machine", displayProduct: "Espresso Machine",
            category: "Kitchen", count: 5, lastUsedAt: .now)
        #expect(freshStrong.hintStrength > 0.9)

        let freshSingle = ProductCategoryMemory(
            normalizedProduct: "espresso machine", displayProduct: "Espresso Machine",
            category: "Kitchen", count: 1, lastUsedAt: .now)
        #expect(freshSingle.hintStrength >= 0.25) // fresh one-off still suggests
        #expect(freshSingle.hintStrength < 0.7)

        let staleSingle = ProductCategoryMemory(
            normalizedProduct: "espresso machine", displayProduct: "Espresso Machine",
            category: "Kitchen", count: 1,
            lastUsedAt: Calendar.current.date(byAdding: .day, value: -400, to: .now)!)
        #expect(staleSingle.hintStrength < 0.25) // faded below the gate

        let staleStrong = ProductCategoryMemory(
            normalizedProduct: "espresso machine", displayProduct: "Espresso Machine",
            category: "Kitchen", count: 10,
            lastUsedAt: Calendar.current.date(byAdding: .day, value: -400, to: .now)!)
        #expect(staleStrong.hintStrength >= 0.25) // strong evidence survives staleness
    }

    @Test @MainActor func freshMemorySuggestsCategory() throws {
        let context = try makeContext()
        context.insert(ProductCategoryMemory(
            normalizedProduct: MerchantLearningService.normalizeProductName("Espresso Machine"),
            displayProduct: "Espresso Machine",
            category: "Kitchen", count: 2, lastUsedAt: .now))

        let service = MerchantLearningService(modelContext: context)
        #expect(service.productCategorySuggestion(for: "Espresso Machine") == "Kitchen")
    }

    @Test @MainActor func staleOneOffMemoryStaysQuiet() throws {
        let context = try makeContext()
        context.insert(ProductCategoryMemory(
            normalizedProduct: MerchantLearningService.normalizeProductName("Espresso Machine"),
            displayProduct: "Espresso Machine",
            category: "Kitchen", count: 1,
            lastUsedAt: Calendar.current.date(byAdding: .day, value: -400, to: .now)!))

        let service = MerchantLearningService(modelContext: context)
        #expect(service.productCategorySuggestion(for: "Espresso Machine") == nil)
    }
}
