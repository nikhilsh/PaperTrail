//
//  PlusGateTests.swift
//  PaperTrailTests
//
//  Coverage for PaperTrail Plus's pure gate logic: the flag-off/flag-on x
//  hasPlus matrix behind `PlusEntitlements.canUseHousehold`, plus the static
//  configuration in `PlusConfig` (free-forever list, product IDs). No
//  StoreKit involved — these are the pieces that are actually testable
//  without a live StoreKit test session.
//

import Testing
import Foundation
@testable import PaperTrail

struct PlusGateTests {

    // MARK: - canUseHousehold matrix

    @Test func flagOffAlwaysAllowsHouseholdRegardlessOfPlus() {
        #expect(PlusEntitlements.canUseHousehold(flagEnabled: false, hasPlus: false) == true)
        #expect(PlusEntitlements.canUseHousehold(flagEnabled: false, hasPlus: true) == true)
    }

    @Test func flagOnRequiresPlusToUseHousehold() {
        #expect(PlusEntitlements.canUseHousehold(flagEnabled: true, hasPlus: false) == false)
        #expect(PlusEntitlements.canUseHousehold(flagEnabled: true, hasPlus: true) == true)
    }

    // MARK: - PlusConfig

    @Test func masterSwitchIsOffByDefault() {
        // ASC products don't exist yet — this MUST stay false until they do
        // and StoreKit integration is verified on-device.
        #expect(PlusConfig.enabled == false)
    }

    @Test func freeForeverListIsNonEmpty() {
        #expect(!PlusConfig.freeForever.isEmpty)
    }

    @Test func freeForeverListHasNoBlankEntries() {
        #expect(PlusConfig.freeForever.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test func benefitsListHasThreeEntries() {
        // docs/MONETIZATION.md names exactly three Plus benefits.
        #expect(PlusConfig.benefits.count == 3)
    }

    @Test func productIDsAreDistinctAndNonEmpty() {
        let ids = PlusConfig.ProductID.all
        #expect(ids.count == 3)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { !$0.isEmpty })
        #expect(ids.contains(PlusConfig.ProductID.monthly))
        #expect(ids.contains(PlusConfig.ProductID.yearly))
        #expect(ids.contains(PlusConfig.ProductID.lifetime))
    }
}
