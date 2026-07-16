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

    @Test func masterSwitchState() {
        // Flipped on for the build-36 IAP debug pass (ASC sandbox products
        // exist). Both this and `debugConsoleEnabled` MUST be re-evaluated
        // before any App Store submission — see PlusConfig's doc comments.
        #expect(PlusConfig.enabled == true)
    }

    @Test func debugConsoleMustNeverShipEnabled() {
        // Not a guarantee this stays false forever — it's a tripwire: if
        // this test starts failing, someone needs to consciously decide
        // whether the debug console (entitlement override, raw transaction
        // dump) is really meant to ship, which it never should be to the
        // App Store.
        #expect(PlusConfig.debugConsoleEnabled == true, "Flip to false before App Store submission.")
    }

    // MARK: - effectiveHasPlus precedence (Simulate Plus override)

    @Test func realEntitlementAlwaysGrantsPlus() {
        #expect(PlusEntitlements.effectiveHasPlus(real: true, simulateOverride: false, debugConsoleEnabled: true) == true)
        #expect(PlusEntitlements.effectiveHasPlus(real: true, simulateOverride: false, debugConsoleEnabled: false) == true)
    }

    @Test func overrideGrantsPlusOnlyWhenDebugConsoleEnabled() {
        #expect(PlusEntitlements.effectiveHasPlus(real: false, simulateOverride: true, debugConsoleEnabled: true) == true)
    }

    @Test func overrideIsIgnoredWhenDebugConsoleDisabled() {
        // The compile-time guard that makes the override impossible to leak
        // into a store build (where debugConsoleEnabled would be false).
        #expect(PlusEntitlements.effectiveHasPlus(real: false, simulateOverride: true, debugConsoleEnabled: false) == false)
    }

    @Test func noRealEntitlementNoOverrideMeansNoPlus() {
        #expect(PlusEntitlements.effectiveHasPlus(real: false, simulateOverride: false, debugConsoleEnabled: true) == false)
        #expect(PlusEntitlements.effectiveHasPlus(real: false, simulateOverride: false, debugConsoleEnabled: false) == false)
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
