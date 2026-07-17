# PaperTrail — Build Review · 17 Jul 2026
> Implementation instructions: `CLAUDE_PROMPT_POLISH.md` (run after V2 + V3 prompts).
Screenshots of the live build vs DESIGN_LANGUAGE.md + v3 specs. Fix in priority order. IDs referenced from `PaperTrail Widget Review.html`.

## A. Widgets (shelfWidgets flag) — logic first, paint second

**W1 · Urgency logic is dishonest (P0).** "CLOSING SOON" shows items 321/324 days out with amber dots. Amber = expiring is a state, not a decoration (DL §4 Pill). Rules:
- Show an item in "Closing soon" only if a window ends ≤ 60 days (return windows: always, they're short).
- Otherwise render the **quiet state**: "Nothing closing soon." + next expiry + portfolio line. Never manufacture urgency.
- Pill colors by real state: sage ≥ 60d · amber < 60d · terra < 7d.

**W2 · Unit inconsistency (P0).** Same number rendered "321 days", "321d", while the app says "10 mo". One formatter everywhere: ≥ 90d → months ("10 mo"); 8–89d → days ("34 days"); ≤ 7d → amber "6 days"; last day → "today".

**W3 · Small "Next up" headline truncates (P0).** "Warranty…" as the serif headline is the event *type*, cut off. Headline = **item name** (serif), sub = the stake ("Warranty ends 3 Jun 2027"), footer = mono months-left. Never headline a truncated category word.

**W4 · Small countdown widget reads as an alarm (P1).** "321d" in 40pt gold for a non-urgent item is a false siren. This slot should be the **coverage ring** small widget from spec C1: sage ring, serif "4/5", mono "COVERED · $3,116". (A per-item countdown is fine later as a *user-configured* widget — see options board.)

**W5 · Large list widget: cut (P1).** It duplicates the medium with less info per row and no dates. Not in spec. If a large ever earns shelf space it must add something (ring + rows + last-added); for now ship Small ×2 + Medium + lock screen only.

**W6 · Dark widget chrome (P2).** Flat #000-ish. Spec: ink gradient `#221C15→#171310` + 0.5px cream hairline outline + gold kicker. Item names in serif, metadata in mono — currently mixed sans.

**W7 · Dates need years when far out (P2).** "Warranty ends 3 Jun" 321 days ahead is ambiguous → "3 Jun 2027".

## B. App screens

**B1 · Pricing = Monthly + Annual + Lifetime (RESOLVED — spec updated).** DL §7 now blesses three plans. The shipped LIFETIME gold card is correct as-is. Remaining work: paywall P1 must list all three (Annual default-selected with ≈/month math, Monthly, Lifetime as a quiet third row — no fake discounts, no countdown); Annual/Monthly member cards show renewal date + MANAGE link.

**B2 · Warranty answer screen uses a slider-looking bar (P1).** The horizontal progress bar with a round knob invites dragging. Spec has two blessed progress idioms: the **coverage ring** (W2) or the **timeline spine**. Use the ring here (matches the passport) with BOUGHT/TODAY/EXPIRES as a ledger row beneath. Also: bottom half of the screen is empty — lift PROOF ON FILE + actions up; add "View full passport →".

**B3 · Library status pills illegible (P0).** "COVERED · 10 MO LEFT" is pale sage on pale sage. On paper cards: text `sageDeep #6E8550`, bg `rgba(147,168,111,.18)`, dot sage. Contrast ≥ 4.5:1.

**B4 · Floating nav collides with content (P1).** On dossier scroll, Back/share/edit pills overlap card content and the segmented control slides under the status bar. Add a top scrim (ink900 → transparent, ~120pt) behind the nav layer, and give the dossier a collapsing header so tabs never sit under the clock.

**B5 · OCR shouting + vendor truncation (P2).** Display names title-cased ("Rheem Storage Heater 20L"); keep raw OCR string in Details. Vendors get a short display name ("Gain City") — "GAIN CITY BEST-ELECTRI…" never truncates mid-word on a card.

**B6 · Category icon mismatch (P2).** Water heater shows the teacup icon. Audit the category→icon map; default to a neutral appliance glyph when unsure, never a wrong-but-confident one.

**B7 · Toggle green (P3).** Household/share toggles look iOS-system green; spec sage `#93A86F`.

## C. What's faithfully built (keep)
Paper-on-ink discipline, dog-ears + stamps, serif/mono/SF separation, honest empty states ("Not recorded — add from your warranty card"), proof score card, household screen copy, ledger dotted leaders, passport ring. The foundation reads as designed — this list is trim, not surgery.
