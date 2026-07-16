# Claude Code kickoff — PaperTrail v3 (flagged)

Paste this to Claude Code in the app repo:

---

Implement the v3 feature pass for PaperTrail (SwiftUI, iOS 17+). Source of truth, in order:

1. `handoff/V3_BRIEF.md` — build ALL nine flagged features (§1–9) exactly as specced, starting with §0 flag architecture: `FeatureFlags.swift`, `APPSTORE` compilation condition hard-off in the App Store build configuration (no remote override), runtime Flags screen under Advanced & Diagnostics in debug/TestFlight builds.
2. `handoff/DESIGN_LANGUAGE.md` — tokens, components, voice. Reuse the existing ArchiveTheme components.
3. `handoff/ANIMATION_SPEC.md` + V3_BRIEF §9 — motion; all ten new animations behind `animPassV3`.
4. `PaperTrail v3 Ideas.html` — sections C1–C3 are the widget, dossier, and add-sheet mockups; section D is the animation map.
5. `PaperTrail v3 Screens.html` — pixel references for the remaining screens: pass-it-on builder, multi-coverage passport rows, debug Flags screen, Siri snippet card, monthly digest. Every v3 screen now has a mockup — copy them, don't improvise.

Order of work: FeatureFlags + Flags screen → multiCoverage (model + passport rows) → addSheetV2 → serviceLedger + manualOnFile (dossier tabs) → shelfWidgets → siriIntents → recallWatch (fixture-data adapter) → passItOn → animPassV3.

Hard constraints: the `APPSTORE` build must be pixel-identical to v2 with every flag compiled off; new CloudKit fields additive + optional; recall notifications are the only category exempt from the 2/month cap; no new third-party dependencies; email-forwarding row shows "Coming soon" until backend exists. Every acceptance criterion in V3_BRIEF.md must pass.

---
