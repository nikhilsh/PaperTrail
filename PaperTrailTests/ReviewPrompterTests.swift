import Testing
import Foundation
@testable import PaperTrail

/// Coverage for the review-prompt delight gates: ≥5 records saved lifetime,
/// never in the first-ever session, never after an error, and at most once
/// per app version.
struct ReviewPrompterTests {

    // MARK: - Pure eligibility logic

    @Test func requiresFiveRecordsLifetime() {
        #expect(!ReviewEligibility.shouldPrompt(
            recordsSavedLifetime: 4, isFirstSession: false,
            lastPromptedVersion: nil, currentVersion: "1.0"
        ))
        #expect(ReviewEligibility.shouldPrompt(
            recordsSavedLifetime: 5, isFirstSession: false,
            lastPromptedVersion: nil, currentVersion: "1.0"
        ))
    }

    @Test func neverPromptsInFirstSession() {
        #expect(!ReviewEligibility.shouldPrompt(
            recordsSavedLifetime: 100, isFirstSession: true,
            lastPromptedVersion: nil, currentVersion: "1.0"
        ))
    }

    @Test func atMostOncePerVersion() {
        #expect(!ReviewEligibility.shouldPrompt(
            recordsSavedLifetime: 10, isFirstSession: false,
            lastPromptedVersion: "1.0", currentVersion: "1.0"
        ))
        #expect(ReviewEligibility.shouldPrompt(
            recordsSavedLifetime: 10, isFirstSession: false,
            lastPromptedVersion: "1.0", currentVersion: "1.1"
        ))
    }

    @Test func neverPromptsWithoutAKnownCurrentVersion() {
        #expect(!ReviewEligibility.shouldPrompt(
            recordsSavedLifetime: 10, isFirstSession: false,
            lastPromptedVersion: nil, currentVersion: nil
        ))
        #expect(!ReviewEligibility.shouldPrompt(
            recordsSavedLifetime: 10, isFirstSession: false,
            lastPromptedVersion: nil, currentVersion: ""
        ))
    }

    // MARK: - ReviewPrompter (UserDefaults-backed) integration

    /// Fresh, isolated UserDefaults suite per call so tests never share state
    /// with each other or with the app's real defaults.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ReviewPrompterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test @MainActor func doesNotPromptBelowThreshold() {
        let prompter = ReviewPrompter(defaults: makeDefaults())
        // A prior run already completed a session, so this isn't the first.
        prompter.recordsSaved(4)
        #expect(!prompter.shouldPrompt)
    }

    @Test @MainActor func promptsOnceThresholdReachedAfterFirstSession() {
        let defaults = makeDefaults()
        // Simulate a prior launch already having happened.
        defaults.set(true, forKey: "reviewPrompt.hasLaunchedBefore")

        let prompter = ReviewPrompter(defaults: defaults)
        #expect(!prompter.shouldPrompt)

        prompter.recordsSaved(5)
        #expect(prompter.shouldPrompt)
    }

    @Test @MainActor func firstEverSessionNeverPrompts() {
        let defaults = makeDefaults()
        // No "hasLaunchedBefore" flag yet — this is the first-ever session.
        let prompter = ReviewPrompter(defaults: defaults)

        prompter.recordsSaved(10)
        #expect(!prompter.shouldPrompt)
    }

    @Test @MainActor func didPromptSuppressesFurtherPromptsThisVersion() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "reviewPrompt.hasLaunchedBefore")

        let prompter = ReviewPrompter(defaults: defaults)
        prompter.recordsSaved(5)
        #expect(prompter.shouldPrompt)

        prompter.didPrompt()
        #expect(!prompter.shouldPrompt)

        // Same version, more delight moments — should stay quiet.
        prompter.claimPacketExported()
        #expect(!prompter.shouldPrompt)
    }

    @Test @MainActor func claimPacketExportCanTriggerPrompt() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "reviewPrompt.hasLaunchedBefore")
        // Threshold was already crossed in an earlier session.
        defaults.set(5, forKey: "reviewPrompt.recordsSavedLifetime")

        let prompter = ReviewPrompter(defaults: defaults)
        #expect(!prompter.shouldPrompt)

        prompter.claimPacketExported()
        #expect(prompter.shouldPrompt)
    }
}
