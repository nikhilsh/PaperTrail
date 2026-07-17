# CLAUDE CODE — PaperTrail Polish Pass (v3.1)
You are fixing a **live build** against its design spec. This is a punch-list pass, not a redesign — do not restyle anything not listed here. Run AFTER `CLAUDE_PROMPT_V2.md` and `CLAUDE_PROMPT_V3.md` work is in place.

## Read first
1. `BUILD_REVIEW.md` — the authoritative punch list (W1–W7 widgets, B1–B7 app). Every item below references its ID.
2. `DESIGN_LANGUAGE.md` — tokens/components. §7 updated 17 Jul: pricing is now Monthly + Annual + **Lifetime**.
3. `PaperTrail Widget Review.html` — pixel reference for the corrected widget set (section B) and the widget logic table.

## Order of work

### 1. Shared date/duration formatter (W2, W7) — do this first, everything depends on it
One `CoverageFormatter` used by app + widgets + notifications:
- ≥ 90 days left → months: `10 mo`
- 8–89 days → `34 days`
- ≤ 7 days → `6 days` (amber context)
- last day → `today`
- Absolute dates include the year whenever the date is > 6 months away: `3 Jun 2027`.
Delete every ad-hoc `321d` / `321 days` formatting site.

### 2. Widget logic (W1) + surfaces (W3–W6)
- "Closing soon" qualifier: return windows always; warranty expiry only ≤ 60 days out; register nudge only ≤ 30 days after purchase. Max 2 rows, nearest first.
- **Quiet state is the default design**: "Nothing closing soon." + next expiry line + `5 ITEMS · $3,116 ON FILE` + sage `ALL COVERED` pill. Never render amber above 60 days (pill: sage ≥ 60d, amber < 60d, terra < 7d/expired).
- Small paper widget = **coverage ring** (replaces the `321d` countdown): sage arc, serif `4/5`, mono `COVERED · $3,116`, dog-ear fold.
- Small dark "Next up": headline = **item name** (serif), sub = stake with year ("Warranty ends 3 Jun 2027"), footer = mono `10 MO LEFT`. Never a truncated event-type headline.
- **Delete the large widget.** Shipped set: small ×2, medium, lock-screen inline. Add lock-screen circular **quick-shelve** (gold library glyph → scanner deep link).
- Lock-screen inline: urgent line when something ≤ 14 days, else `5 items covered · next: Jun 2027`.
- Dark widgets: ink gradient `#221C15→#171310` + 0.5px cream hairline, gold mono kicker. Deep links: ring → Coverage tab, row → dossier, quick-shelve → scanner. Reload on data change + daily 09:00. No motion, no shimmer.

### 3. Paywall & member card (B1)
- Paywall P1: three plans — Annual default-selected with ≈/month math, Monthly, Lifetime as a quiet third row ("Purchased once. Yours forever."). No countdowns, no fake discounts, ✕ always visible.
- Member card: Annual/Monthly variants show renewal date + MANAGE deep link; Lifetime keeps NEVER EXPIRES. Current Lifetime card is correct.

### 4. Warranty answer screen (B2)
Replace the knob-slider progress bar with the **coverage ring** (same component as the passport, 9pt stroke, animate once on appear, 600ms easeOut). BOUGHT / EXPIRES as ledger rows (mono key … dotted leader … value) beneath. Lift PROOF ON FILE and the actions up; add `VIEW FULL PASSPORT →` secondary button. No dead bottom half.

### 5. Library pills (B3)
Status pill on paper cards: text `#6E8550` (sageDeep), bg `rgba(147,168,111,.18)`, sage dot. Verify ≥ 4.5:1 contrast in both urgency variants (amber: text `#8A6420` on `rgba(215,166,76,.18)`).

### 6. Dossier scroll chrome (B4)
Top scrim behind floating nav pills: ink900 → transparent, ~120pt, so Back/share/edit never sit on raw card content. Segmented control must never slide under the status bar — collapse it into the header or pin below the safe area.

### 7. Display names (B5) + icons (B6) + toggles (B7)
- Title-case OCR names for display ("Rheem Storage Heater 20L"); keep raw string in Details → Model.
- Vendor display name shortened at first legal suffix ("Gain City") — never mid-word ellipsis on cards.
- Category→icon audit: water heater ≠ teacup. Unknown category → neutral appliance glyph.
- All toggles: sage `#93A86F` on-state, not system green.

## Hard constraints (unchanged)
- All widget work stays behind `shelfWidgets`; `APPSTORE` build pixel-identical to v2 with flags off.
- Butler voice: no urgency theatre, ≤ 2 notifications/month, honest states only.
- Formatter change (step 1) applies app-wide — it is the one deliberate cross-cutting change; screenshot-diff the rest.
