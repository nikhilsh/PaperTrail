# PaperTrail v3 design handoff

Sequencing per Nik (2026-07-16): **the v2 pass (docs/design-v2/, CLAUDE_PROMPT_V2) ships
first**, then this v3 pass — nine features, every one behind a compile-time flag
(`FeatureFlags.swift` + `APPSTORE` compilation condition; see V3_BRIEF.md §0). The
previous packets (design-v2) are subsets of this program.

Files here:
- `V3_BRIEF.md` — the nine flagged features + flag architecture + acceptance criteria
- `CLAUDE_PROMPT_V3.md` — the kickoff prompt (run after CLAUDE_PROMPT_V2)
- `PaperTrail v3 Screens.html` — pixel mockups: pass-it-on builder, multi-coverage
  passport, Flags screen, Siri snippet, monthly digest
- `PaperTrail v3 Ideas.html` — competitor scan, ranked feature ideas, hero mockups
  (widgets / dossier / add sheet), animation map

Canonical source (interactive): the "Papertrail" claude.ai/design project
(id 5cb2c8db-4316-4521-9b6e-1ef37582b68d), files under `handoff-v2/`. Tokens and
component specs shared with v2: `docs/design-v2/DESIGN_LANGUAGE.md` + `pt.css`.

Repo-reality notes (differences from the brief's assumptions):
- Product IDs: the app uses `plus.monthly` / `plus.yearly` (ASC-created), not
  `com.papertrail.plus.*`; Plus is subscription-only per Nik's 2026-07-16 decision.
- A widget extension target + Expiring Soon widget already exist (Wave 3); the
  `shelfWidgets` flag governs the v3 paper-aesthetic redesign/additions.
- `coverageLinesData` (additive JSON field) shipped in v2 Wave C with a simpler shape
  (label, covered); `multiCoverage` extends the codable with optional fields
  (start/end/kind/coveredItems) — versioned decode, never a breaking change.
- Siri/Spotlight basics (App Intents, CSSearchableItem) shipped in Wave 1; `siriIntents`
  covers the snippet cards + AddItemIntent.
- The repo is iOS 26+ (brief says 17+ — ignore).
