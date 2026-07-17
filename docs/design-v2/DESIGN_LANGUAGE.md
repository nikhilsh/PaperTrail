# PaperTrail — "The Archive" Design Language (v2)
Spec for implementation in SwiftUI. Everything here maps 1:1 to `pt.css` in the prototype.

## 1. Principles
1. **A library, not a dashboard.** Calm, warm, archival. Every screen answers one question.
2. **Paper on dark.** Cream documents (`paper`) float on warm near-black (`ink`). Paper = *the user's records*. Dark chrome = *the app*. Never invert.
3. **Gold is earned.** Foil gradients only for: Plus, primary CTA, active tab, the FAB. Never decorative.
4. **Honest states.** Sync, permissions, coverage: say the true state ("Backup paused · retry"), never fake green.
5. **≤ 5 rows per settings screen.** Anything technical lives under Advanced & Diagnostics.
6. **Butler voice.** Notifications ≤ 2/month, no marketing toggle exists at all.

## 2. Color tokens (SwiftUI `Color(hex:)`)
| Token | Hex | Use |
|---|---|---|
| ink900 | #0E0C09 | App background |
| ink850 | #13110D | Tab bar fade, sheets |
| ink750 | #221C15 | Grouped list cards |
| paper | #F3EBD9 → grad #F6EEDD→#E9DEC5 | Record cards, certificates |
| paperFold | #D6C7A2 | Dog-ear triangle |
| onPaper | #211C12 | Ink on cream |
| onPaper2 | #5F5641 | Secondary on cream |
| txt | #EFE6D2 | Primary on dark |
| txt2 | #C2B89E | Secondary on dark |
| txt3 | #938A70 | Tertiary/labels on dark |
| gold | #C2A15C (hi #E0C588, deep #8A6E3A) | Foil gradient stops |
| sage | #93A86F (deep #6E8550) | Covered / success |
| amber | #D7A64C | Expiring / closing soon |
| terra | #C56A45 | Expired / error |
| hairline | rgba(231,220,196,0.14) | Row separators |

Gold foil gradient: `linear(90°, goldDeep, gold 40%, goldHi 52%, gold 64%, goldDeep)`.

## 3. Type
- **Display/serif:** Newsreader (fallback: New York via `.serif` design). Titles 32–40pt semibold, tight leading (1.02), -1% tracking. Italic for warm asides ("covered.", taglines).
- **Mono:** IBM Plex Mono. ALL-CAPS labels 9.5–11pt, tracking .14–.26em. Used for: kickers, values, dates, pills, buttons.
- **Body:** SF Pro (system). Rows 15.5pt/500, sublabels 12pt txt3.
- Never mix: serif = titles + record names; mono = metadata; SF = body/controls.

## 4. Core components
- **PaperCard**: cream gradient, 14pt radius, grain (0.05 multiply noise), optional dog-ear (20pt corner clip + fold triangle). Shadow: `0 18 34 -20 black70`.
- **SettingsRow**: 34pt icon tile (radius 9, 6% cream fill, gold stroke icon) + title/sub + mono value + chevron. Grouped in ink750 card, hairline separators.
- **Pill**: mono 10pt caps, dot; covered=sage, expiring=amber, expired=terra, ghost=cream 7%.
- **Stamp**: 2pt border currentColor, mono caps, rotate −3°. States: covered (sageDeep), expired (terra), paper (goldDeep).
- **GoldRule**: 2pt foil gradient divider (the icon motif).
- **Buttons**: full-width, mono caps 12pt. Primary = cream-gold gradient w/ gold glow; Secondary = 1px hairline outline.
- **Toggle**: sage on-state (not iOS green).
- **FAB**: 54pt gold radial circle, serif "+", 36pt gold glow.
- **Toast**: dark blur pill, bottom 108.

## 5. New v2 patterns (from explorations)
- **Plus band on library card** (S1): foil band fused to card bottom — identity + upgrade as one object.
- **Folder-tab cards** (S2): mono tab sticking above paper card, 8pt top radii.
- **Ledger rows** (S3): mono key … dotted leader … value. For dense read-only lists.
- **Timeline spine** (W1): 2pt vertical line, sage-filled past nodes, gold glowing "today", hollow future. Future nodes are editable actions.
- **Coverage ring** (W2): 9pt stroke, sage arc on 12% track, serif center.
- **Receipt sheet** (P2): mono lines, dashed dividers, zigzag bottom edge, barcode strip.
- **Gold member card** (P3): foil gradient card, member №, "NEVER EXPIRES".
- **Soft-ask sheet** (N1): paper sheet over dimmed app, shows a real example notification, then triggers the iOS prompt.

## 6. Voice & copy rules
- Sentence case everywhere except mono labels (ALL CAPS).
- Speak to the stake, not the feature: "Know the day coverage ends", "Last day to change your mind is 22 Jul".
- Reassure in the same breath as warning: "…Your proof is ready if you need it."
- Numbers are the user's own ($3,116, 5 items) — never invented stats.
- Forbidden: "unlock", "supercharge", exclamation marks, urgency countdowns on paywalls.

## 7. IAP presentation rules (subscription)
- Plus is a **membership** — framed as your library card, never "unlock features".
- Three plans (updated 17 Jul 2026): Annual (default-selected, ≈/month math shown), Monthly, and **Lifetime** ("Purchased once. Yours forever.") presented as a quiet third row, not a countdown-driven upsell.
- Trial: "First 2 weeks free" — always stated with the renewal price in the same breath.
- Honesty is the differentiator: "We'll remind you before every renewal. Cancel keeps everything." Renewal reminder is a REAL notification (counts toward the 2/month cap in its month).
- Anchor against a denied claim (~$300), not against other subscriptions.
- Paywall dismissible ✕ top-right, Restore/Privacy/Terms always visible. No countdowns, no fake discounts, no pre-selected upsells.
- Post-purchase: library card re-strikes in gold (P3) with MEMBER Nº · plan. Annual/Monthly show renewal date + MANAGE link (deep-link to App Store subscription settings); Lifetime shows NEVER EXPIRES + "Purchased once. Yours forever." — no manage link needed.
- Lapsed state: gold card fades back to cream with a quiet "Renew your card" band. Nothing is deleted; free features keep working — data is never hostage.

## 8. Notifications
Types: warranty-ending (once, at user-set lead), return-window (once), coverage-line reminders (v3 `multiCoverage`, once per dated line/cluster at lead-time only — no day-of nudge, deduped within 7 days of each other and of the record's own warranty-ending reminder), monthly digest (1st, 9am), registration nudge (once, 3 days after add). Hard cap ≈2/month; digest absorbs overflow. Safety recall notices (v3 `recallWatch`) are the one exception to the cap: they fire on every new real match regardless of budget, since a safety alert overrides the "don't nag" promise — never for fixture/preview data, which is never allowed to trigger a real notification. Title = item + stake; body = date + reassurance. No promotional category exists.

## 9. Motion
- Push: slideIn 280ms cubic-bezier(.2,.7,.3,1); back 260ms; sheets fade+scale 220ms.
- Gold glow pulses only on first appearance of Plus band (once per install).
- Ring/progress animate on appear, 600ms easeOut, never loop.

## 10. iOS mapping notes
- Grouped lists: `List` with `.insetGrouped`, custom row background ink750.
- Paper grain: pre-rendered noise PNG at 5% multiply, not runtime turbulence.
- Dog-ear: `UnevenRoundedRectangle` + custom `Shape` clip w/ fold triangle overlay.
- Haptics: `.success` on claim packet built; `.light` on toggle; none on paywall.
