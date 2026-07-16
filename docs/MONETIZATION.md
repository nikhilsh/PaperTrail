# PaperTrail Monetization

Drafted 2026-07-15 from the July 2026 competitive scan. Principle first, price second.

## The principle: charge for the payoff, never for entry or exit

The category's three fatal user complaints are entry friction, data-loss/lock-in
anxiety, and subscription resentment ("$500/yr for a database with a camera" — Sortly
renewals up 300%+; Centriq shut down and deleted user data). PaperTrail's structural
advantage: extraction runs on-device, so **a scan costs us $0** — cloud-OCR competitors
(Veryfi $500/mo minimum, Taggun $0.04–0.06/doc) must cap free scans; we never have to.

Therefore, **free forever, explicitly promised**:
- Unlimited scanning, OCR, and AI extraction
- Unlimited records and local/iCloud private storage
- Export everything (PDF + CSV) — the anti-lock-in guarantee is a trust feature and
  must never be paywalled
- Warranty + return-window reminders (the basic per-record ones)
- No account, no email, no tracking — unchanged

**Paid — "PaperTrail Plus"** (working name), the payoff moments:
- **Household sharing** (the whole Milestone 4 feature) — sharing with 1 member free
  (get the habit + virality), unlimited household requires Plus. Cleanest gate: the
  invite flow checks entitlement before `makeShare()` when participants ≥ 1.
- **Insurance-Ready Report** (Wave 2) — the artifact people show an insurer/mover.
  Free tier: one room; Plus: whole home + household-wide.
- **Warranty Digest Pro** (Wave 2) — the monthly money-saved digest + "check for
  defects before coverage ends" nudges. Basic per-record reminders stay free.
- Later candidates: Warranty Brain, recall alerts, widgets stay free (visibility),
  claim packet stays free (it IS the app's promise — gating it would poison trust).

## Price points (from the scan's bimodal market data)

Consumer willingness clusters at $1–5/mo, $15–45/yr, or $15–40 lifetime; anything
higher reads as business pricing and enrages households.

- **Plus monthly**: US$2.99/mo (SGD 3.98 tier)
- **Plus annual**: US$19.99/yr (~44% saving — the anchor we actually want people on)
- **Lifetime**: US$49.99 non-consumable — offered but not promoted; it answers the
  anti-subscription crowd (WHIG $38, Nest Egg one-time prove demand) while the price
  respects the Weather-Line lesson (don't underprice a perpetual promise)
- Free trial: 14 days on the annual (intro offer), no trial on monthly
- Family Sharing: ON for the subscription (household app — fighting it is absurd)

## Technical plan (StoreKit 2, no server)

1. **Products** (App Store Connect):
   - Subscription group "PaperTrail Plus": `plus.monthly`, `plus.yearly` (14-day
     intro trial on yearly)
   - Non-consumable: `plus.lifetime`
2. **Entitlement layer**: a small `Entitlements` @Observable singleton wrapping
   StoreKit 2 — `Transaction.currentEntitlements` on launch + `Transaction.updates`
   listener; publishes `hasPlus: Bool`. On-device receipt validation only (StoreKit 2
   JWS is verified locally); no server, consistent with the no-account posture.
   Persist last-known state for offline launches. Restore = automatic with StoreKit 2
   (plus a manual "Restore purchases" row in Settings for App Review).
3. **Gating**: single choke points, never scattered ifs —
   `HouseholdManager.makeShare()` (participant count), report generator (room scope),
   digest scheduler. Each gate shows the same paywall sheet.
4. **Paywall**: one themed sheet (The Archive style) stating the free-forever list
   *on the paywall itself* (trust move: show what you're NOT paying for), the three
   Plus benefits, price toggle, restore + privacy/terms links. No dark patterns: no
   fake urgency, no pre-selected upsell, close button immediately visible.
5. **CI/compliance**: StoreKit configuration file for tests; App Review needs a
   restore button, terms/privacy links (site already live), and if lifetime +
   subscription coexist, clear copy on the difference.
6. **ASC setup** is scriptable via the ASC API key already in use (products, prices,
   review notes) — automate when we build this.

## Sequencing

Ship monetization only after Wave 1 + Wave 2 exist (the paid tier needs the insurance
report + digest to be real) and household sharing has survived a store release. Target:
the store update *after* the flag-on household release. No grandfathering needed:
household sharing has never reached App Store users (the store build has always been
flag-off for it) — only the developer's own OTA test devices have used it, so there's
nobody to carry forward free.

## What we will never do

Sell or monetize user data (the Fetch/Receipt Hog model is the anti-PaperTrail);
paywall export or data access; cap free records; auto-renew dark patterns; price the
household tier like B2B software.
