# Claude Code kickoff — PaperTrail v2

Paste this to Claude Code in the app repo:

---

Implement the "v2" design pass for PaperTrail (SwiftUI, iOS 17+, StoreKit 2, CloudKit). The design team shipped four documents — treat them as the source of truth, in this order:

1. `handoff/V2_BRIEF.md` — what to build (Settings S1, Coverage Passport W2, Membership Certificate paywall P1 — subscription, gold member card P3 with renewal state, notification soft-ask N1, App Store assets).
2. `handoff/DESIGN_LANGUAGE.md` — tokens, type, components, voice. Build `ArchiveTheme.swift` + component library (`PaperCard`, `SettingsRow`, `Pill`, `Stamp`, `GoldRule`, `FoilButton`, `CoverageRing`, `GoldMemberCard`, `PlusBand`, `CertificateView`, `SoftAskSheet`) before any screens.
3. `handoff/ANIMATION_SPEC.md` — every motion, curve, and the Reduce Motion fallbacks.
4. `PaperTrail v2 Prototype.html` — open in a browser and interact; it demonstrates the paywall purchase flow, gold strike, ring animation, soft-ask, and serial copy exactly as intended.

Order of work: theme + components → Settings restructure (keep all existing functionality one level down, ≤5 top-level rows) → Coverage Passport (extend the record model with coverageLines + supportContact) → paywall + StoreKit (auto-renewable group: `com.papertrail.plus.annual` + `.monthly`, 14-day intro trials, MEMBER-stamp → gold-strike sequence, lapse → cream fallback) → soft-ask (trigger: first item saved, permission undetermined) → screenshot scenes for the App Store panels.

Constraints: no new third-party dependencies; sage toggles via tint; all foil gradients from the shared theme; notifications hard-capped per the spec; nothing may interrupt an in-progress scan. Every acceptance criterion in V2_BRIEF.md must pass.

---
