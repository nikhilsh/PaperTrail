import Testing
import Foundation
@testable import PaperTrail

// This whole suite exercises `Flag`/`FeatureFlags` API that only exists in a
// non-APPSTORE build — see their `#if !APPSTORE` gating. An APPSTORE test
// run would otherwise fail to compile this file rather than cleanly skip it.
#if !APPSTORE

/// Coverage for the v3 flag architecture (`docs/design-v3/V3_BRIEF.md` §0):
/// every flag defaults off, set/read round-trips through an injected
/// `UserDefaults` suite (never the shared App Group suite — tests must never
/// touch real device state), and the `UserDefaults` key format is stable.
/// APPSTORE's hard-off branch isn't covered here: it's a compile-time
/// `#if APPSTORE` that this (Debug/Release) test target never compiles under.
struct FeatureFlagsTests {

    /// A fresh, uniquely-named suite per test so runs never see leftover
    /// state from a previous test or from the app itself.
    private func scratchSuite(_ name: String = #function) -> UserDefaults {
        let suiteName = "FeatureFlagsTests.\(name)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        return suite
    }

    // MARK: - Default state

    @Test func everyFlagDefaultsOff() {
        let suite = scratchSuite()
        for flag in Flag.allCases {
            #expect(FeatureFlags.isOn(flag, suite: suite) == false)
        }
    }

    // MARK: - Set/read round-trip

    @Test func setOnThenIsOnRoundTrips() {
        let suite = scratchSuite()
        FeatureFlags.setOn(true, for: .shelfWidgets, suite: suite)
        #expect(FeatureFlags.isOn(.shelfWidgets, suite: suite) == true)

        FeatureFlags.setOn(false, for: .shelfWidgets, suite: suite)
        #expect(FeatureFlags.isOn(.shelfWidgets, suite: suite) == false)
    }

    @Test func togglingOneFlagDoesNotAffectOthers() {
        let suite = scratchSuite()
        FeatureFlags.setOn(true, for: .passItOn, suite: suite)
        #expect(FeatureFlags.isOn(.passItOn, suite: suite) == true)
        for flag in Flag.allCases where flag != .passItOn {
            #expect(FeatureFlags.isOn(flag, suite: suite) == false)
        }
    }

    @Test func setAllTrueTurnsOnEveryFlag() {
        let suite = scratchSuite()
        FeatureFlags.setAll(true, suite: suite)
        for flag in Flag.allCases {
            #expect(FeatureFlags.isOn(flag, suite: suite) == true)
        }
    }

    @Test func setAllFalseTurnsOffEveryFlag() {
        let suite = scratchSuite()
        FeatureFlags.setAll(true, suite: suite)
        FeatureFlags.setAll(false, suite: suite)
        for flag in Flag.allCases {
            #expect(FeatureFlags.isOn(flag, suite: suite) == false)
        }
    }

    // MARK: - Key format stability

    @Test func keyFormatIsStable() {
        #expect(FeatureFlags.key(for: .shelfWidgets) == "flag.shelfWidgets")
        #expect(FeatureFlags.key(for: .multiCoverage) == "flag.multiCoverage")
        #expect(FeatureFlags.key(for: .addSheetV2) == "flag.addSheetV2")
        #expect(FeatureFlags.key(for: .serviceLedger) == "flag.serviceLedger")
        #expect(FeatureFlags.key(for: .manualOnFile) == "flag.manualOnFile")
        #expect(FeatureFlags.key(for: .recallWatch) == "flag.recallWatch")
        #expect(FeatureFlags.key(for: .passItOn) == "flag.passItOn")
        #expect(FeatureFlags.key(for: .siriIntents) == "flag.siriIntents")
        #expect(FeatureFlags.key(for: .animPassV3) == "flag.animPassV3")
    }

    @Test func allNineFlagsExist() {
        // Tripwire: catches an accidental addition/removal against the
        // brief's fixed nine-feature list.
        #expect(Flag.allCases.count == 9)
    }

    @Test func everyFlagHasANonEmptySubtitle() {
        for flag in Flag.allCases {
            #expect(!flag.subtitle.isEmpty)
        }
    }
}

#endif
