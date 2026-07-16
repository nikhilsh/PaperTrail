# PaperTrail v2 — Implementation Brief
Chosen directions from `PaperTrail v2 Explorations.html`: **S1 + W2 + P1 → P3 + N1 + App Store track 5**.
Read with: `DESIGN_LANGUAGE.md` (tokens/components/voice) and `ANIMATION_SPEC.md` (motion). Live reference: `../PaperTrail v2 Prototype.html`.

## 1. Settings — "Front desk" (S1)
Replace the current Settings top level with exactly:
1. **Library card** (paper, dog-ear): kicker row, avatar, "Your library", backup recency, gold rule, `● SYNCED · 5 ITEMS · $3,116` mono row, and the **Plus band** fused to the card bottom (foil gradient, "PaperTrail Plus / Annual membership · first 2 weeks free / S$29.98/YR ›").
2. **Reminders** row → drill-in (warranty toggle, lead time, return windows, digest, per-type matrix from N2).
3. **Household** row → existing Family Sharing screen.
4. **Your data** row → export / import / privacy screen.
5. **Help & about** row → help, privacy policy, rate, Advanced & Diagnostics.
Footer: two-line privacy sentence. NOTHING else at top level. All current rows survive one level down — no feature deletions.

### Post-purchase state (P3)
The cream library card is replaced by the **gold member card**: foil gradient bg, "PAPERTRAIL · PLUS MEMBER", name, `MEMBER Nº NNNNNN · ANNUAL` (or MONTHLY), stats row, `RENEWS <date>`, footer line "We'll knock 2 weeks before renewal." + MANAGE › (deep-links to App Store manage-subscriptions). Member № = sequential-looking hash of original transaction id (cosmetic only). Plus band disappears.
**Lapsed:** card returns to cream; a quiet "Renew your card — S$29.98/yr" band replaces the Plus band. No data loss, free tier keeps working.

## 2. Warranty page — "Coverage passport" (W2)
Item warranty screen becomes one cream passport card + two groups:
- Passport: kicker + Covered stamp; **coverage ring** (9pt, sage on 12% track) with serif `N mo` center; bought/expires mono row; hairline; **Serial row with COPY button** (UIPasteboard + toast + light haptic); Model row.
- Group: What's covered — parts/labour ✓, named coverage lines ✓/✗ from record data. Unknown → "Not recorded — add from your warranty card".
- Group: **Support contact row** (brand help line, hours; tap = call). Source: on-device brand table; fallback hidden.
- CTA: `Build claim packet` (existing flow), secondary "Something's wrong with it →".
Data additions: `coverageLines: [(String, Bool)]`, `supportContact: (name, phone, hours)?`.

## 3. Paywall — "Membership certificate" (P1, subscription)
Full-screen sheet, dark bg, dismissible ✕ top-right.
- Cream **certificate**: double engraved border (1.5pt gold + inner 1pt), kicker "CERTIFICATE OF MEMBERSHIP", serif title, italic "Renewed yearly, like a library card.", **gold seal** (74pt, radial foil, dashed inner ring, "PLUS · MEMBER · EST 2026"), 4 benefit checks, gold rule, **plan picker** (Annual S$29.98 default w/ ≈S$2.50/mo, Monthly S$3.98), fine print: "First 2 weeks free · then <price>. We'll remind you before every renewal. Cancel keeps everything."
- CTA `Start 2 weeks free`; Restore · Privacy · Terms always visible.
- Purchase flow per ANIMATION_SPEC §3–4 (MEMBER ✓ stamp → gold strike in Settings).
- StoreKit 2: auto-renewable group `plus` — `com.papertrail.plus.annual` (14-day intro trial) + `com.papertrail.plus.monthly` (14-day trial). Restore = `AppStore.sync()`. Renewal-reminder local notification 2 weeks before `renewalDate` (annual only).
- Entry points: Plus band (Settings), gated features (household >1 member, whole-home report, Digest Pro), NOT on first launch, NEVER interrupting a scan.

## 4. Notifications — soft-ask (N1)
- Trigger: after the user's FIRST successful item save (not app launch), and only if permission undetermined.
- Paper sheet over dimmed app: "Before you put this away / May we leave a note?" + promise copy + a rendered sample notification (real item name) + `Yes, notify me` / `NOT NOW` + "iOS will ask to confirm next."
- Yes → system prompt. Not now → re-ask only after a warranty passes within 30 days of expiry (max 1 re-ask, ever).
- Notification categories & copy: DESIGN_LANGUAGE §8. Hard cap ~2/month, digest absorbs overflow.

## 5. App Store listing (track 5)
- Name: `PaperTrail: Warranty Keeper` · Subtitle: `Receipts, proof & reminders`
- 5 screenshot panels (alternating cream/dark, serif caption top): Hook / Covered / Claim packet / Privacy / Membership ("Your card, in gold. Two weeks free."). Captions + full copy in the explorations doc, panel row 5.
- Keywords: `warranty,receipt,tracker,proof,purchase,claim,insurance,home,inventory,return,expiry,guarantee`
- Review nudge: after a claim packet is shared, once: "Did PaperTrail save you a claim? Tell the next person."

## Acceptance criteria
- Settings top level ≤ 5 rows + card; every removed row reachable in ≤ 2 taps.
- Paywall renders complete with dynamic type XL; dismiss always reachable.
- Purchase → gold card survives relaunch and restore-on-new-device; shows correct plan + renewal date.
- Lapse/cancel → cream card returns, no data loss, no nag more than the single renew band.
- Trial state clearly shown on gold card ("TRIAL · BILLS 30 JUL").
- Ring animation honors Reduce Motion (crossfade).
- Serial COPY works with VoiceOver ("Copy serial number, button").
- Soft-ask never appears before first saved item; declining is remembered.
