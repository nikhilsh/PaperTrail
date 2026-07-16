# PaperTrail v2 — "The Archive" design pass

Handoff docs from the design project, committed here so future sessions don't
depend on an external job path. Read in this order:

1. [`V2_BRIEF.md`](V2_BRIEF.md) — what to build: Settings "front desk" (S1),
   Coverage Passport (W2), Lifetime Certificate paywall (P1→P3), notification
   soft-ask (N1), App Store listing assets.
2. [`DESIGN_LANGUAGE.md`](DESIGN_LANGUAGE.md) — tokens, type, components, voice.
3. [`ANIMATION_SPEC.md`](ANIMATION_SPEC.md) — every motion, curve, and the
   Reduce Motion fallback.
4. [`pt.css`](pt.css) — the CSS the SwiftUI tokens map to 1:1 (exact gradients,
   shadows, spacing). Source of truth for pixel values when the `.md` files
   are ambiguous or in conflict with each other.
5. [`CLAUDE_PROMPT_V2.md`](CLAUDE_PROMPT_V2.md) — the original kickoff prompt
   (references an iOS 17+ / four-doc framing that predates this split; kept
   for context, superseded by the docs above).

## Not committed here

The two HTML prototypes (`PaperTrail v2 Explorations.html`,
`PaperTrail v2 Prototype.html`) are too large/binary-ish for the repo. They
live in the design project at `claude.ai/design` (job `9138319b`,
`tmp/redesign/handoff-v2/`) — open the Prototype in a browser to see the
paywall purchase flow, gold strike, coverage-ring animation, soft-ask, and
serial-copy exactly as intended. If that job is no longer reachable, treat
`DESIGN_LANGUAGE.md` + `ANIMATION_SPEC.md` + `pt.css` as complete enough to
rebuild any screen from scratch.

## Fonts

The spec names Newsreader (serif/display) and IBM Plex Mono. The app already
bundles both and vends them through `PTFont.serif`/`PTFont.mono`
(`PaperTrail/Design/PTFonts.swift`) — use `PTFont` as-is; no new font-file
decision needed for this wave.

## Status

Wave A (this commit): theme tokens reconciled into `PTTheme.swift` +
component library in `PaperTrail/Design/V2/`. Library only — no existing
screens rewired. See the Wave A PR description for the full reconciliation
list (what extended an existing component vs. what's genuinely new).
