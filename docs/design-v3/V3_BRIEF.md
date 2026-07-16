# PaperTrail v3 — Feature-Flagged Build Brief
Build EVERYTHING on this list, but behind a compile-time flag: **none of it ships to the App Store until each flag is flipped deliberately.** Design reference: `PaperTrail v3 Ideas.html` (sections B–D) + `PaperTrail v3 Screens.html` (V3-1 pass-it-on builder, V3-2 multi-coverage rows, V3-3 Flags screen, V3-4 Siri snippet, V3-5 monthly digest). Tokens/components/voice: `DESIGN_LANGUAGE.md`. Motion rules: `ANIMATION_SPEC.md` + §7 below.

## 0. Flag architecture (read first)
- Single source of truth: `FeatureFlags.swift`.
  ```swift
  enum Flag: String, CaseIterable {
    case shelfWidgets, multiCoverage, addSheetV2, serviceLedger,
         manualOnFile, recallWatch, passItOn, siriIntents, animPassV3
  }
  struct FeatureFlags {
    static func isOn(_ f: Flag) -> Bool {
      #if APPSTORE
      return false            // hard-off in release — no exceptions, no remote override
      #else
      return UserDefaults.standard.bool(forKey: "flag.\(f.rawValue)")
      #endif
    }
  }
  ```
- `APPSTORE` is a Swift compilation condition set ONLY on the Release/App Store build configuration. Debug/TestFlight-internal builds get a **Flags** screen appended to Advanced & Diagnostics (mock V3-3: amber dashed "compiled out of App Store builds" banner, sage toggles with mono flag names, ALL ON / ALL OFF / MATCH APP STORE shortcuts) so each feature can be demoed independently.
- Every v3 entry point must collapse cleanly when its flag is off: no blank rows, no reserved space, no dead code paths reachable from UI. Ship gate: App Store build must be pixel-identical to v2.
- New model fields (coverage lines, service entries, manuals) are additive + optional in CloudKit so flag-off clients ignore them safely.

## 1. `shelfWidgets` — Shelf widgets (Ideas C1)
- WidgetKit extension, paper aesthetic. Medium: "Closing soon" — up to 2 urgency rows (return window pill, register nudge). Small ×2: coverage ring `4/5 · $3,116`; dark "Next up" card. Lock screen: inline mono one-liner ("TV return · 6 days").
- Deep links: row → item dossier; ring → Coverage tab. Timeline reload on data change + daily 09:00.
- Widget renders pre-filled (static); no placeholder shimmer.

## 2. `multiCoverage` — Multiple coverages per item
- Model: `coverageLines: [CoverageLine]` — `(label, start, end, kind: warranty|extended|insurance, coveredItems: [String])`.
- Passport ring shows the LONGEST live line (mock V3-2: ring left, "3 coverage lines / 2 active · 1 expired / next to lapse" summary right); beneath it one compact row per line with months-left + mini progress bar. Expired lines stay visible, struck through. "+ ADD A COVERAGE LINE" gold mono action below the group.
- Reminders fire per line, deduped into one notification when ≤7 days apart.

## 3. `addSheetV2` — Five ways to shelve (Ideas C3)
- FAB opens the paper sheet: Scan receipt (hero) / Photograph the thing / Forward an email / Scan the barcode / Just say it.
- Photograph: creates a stub card flagged `needsProof` (amber "ADD PROOF" pill in library).
- Email forwarding: show the user's address + copy button; server parsing is backend-dependent — until live, the row shows "Coming soon" in mono and is non-tappable (flag stays on, sub-state handles it).
- Barcode: VisionKit scan → local brand/model lookup; unknown = prefilled manual form.
- Voice: SFSpeechRecognizer, on-device; parse name/price/store/date; show parsed fields for confirmation — never save unconfirmed.

## 4. `serviceLedger` — Service ledger (Ideas C2)
- Dossier gains Proof / Service / Papers segmented tabs (gold active state).
- Service = timeline spine entries: `(date, actor: self|authorized|shop, title, cost, jobRef?, photos[])`. "+ LOG A REPAIR" inline dashed node.
- Claim packet gains optional "Service history" page; resale packet includes it always.

## 5. `manualOnFile` — Manual on file
- Papers tab row: attach PDF from Files, or auto-fetch by model number where the barcode lookup returns a manual URL. Store in the record (CloudKit asset), open in QuickLook.

## 6. `recallWatch` — Recall watch (Plus)
- Background refresh matches model numbers against recall feeds (CPSC + local-market equivalents; feed adapter is its own module — stub with fixture data until sourcing is decided).
- Dossier row states: `✓ Clear · checked <date>` (sage) / `Recall notice — read this` (terra, notification allowed OUTSIDE the 2/month cap — safety exempt) / `Watching…` first-run ellipsis animation.
- Gate behind Plus entitlement AND the flag.

## 7. `passItOn` — Resale packet (Plus)
- Dossier row → builder (mock V3-1): serif headline "A dossier for the next owner.", paper checklist of pages — proof of purchase (price REDACTED), remaining transferable warranty, service history, manual, "Show price paid" (off by default) — live packet-size row, gold CTA "Hand it over".
- Output: single PDF, footer "Kept with PaperTrail". Share sheet. Item then offers "Mark as passed on" → card gets mono `SOLD · PASSED ON` stamp, excluded from totals, kept in a "Passed on" shelf at library bottom.

## 8. `siriIntents` — Siri & Spotlight
- App Intents: `CheckWarrantyIntent(item)` → passport snippet card (mock V3-4: compact paper card — kicker, Covered stamp, item name, plain-language answer, progress bar, OPEN PASSPORT › / BUILD CLAIM); `AddItemIntent` → opens add sheet. CSSearchableItem per record (name, brand, store) — respects Face ID lock (no snippet content when locked).

## 9. `animPassV3` — Animation pass (Ideas D, all ten)
Receipt-prints-on-save 450ms · card-shelving with neighbors parting 380ms · ledger-entry stamp 320ms · recall-check resolve 800ms · claim-packet assembly 1.1s staggered · pass-it-on handover 500ms · gold-bookmark pull-to-refresh (gesture-driven) · odometer numbers 400ms (on change only) · digest page-curl 550ms (digest layout: mock V3-5 — three-stat paper header, "Needs eyes" amber group, "Quiet this month" ✓ group, italic sign-off) · in-app ring first-visit-per-day.
Rules unchanged: once-only, nothing loops, Reduce Motion → 200ms crossfades. Flag off = v2 motion exactly.

## Acceptance criteria
- `APPSTORE` build: zero v3 UI reachable, binary diff of UI = v2; flags screen absent.
- Debug build: every flag independently toggleable at runtime; no flag combination crashes or leaves orphan UI.
- Data written by flagged features is ignored (not destroyed) by flag-off and v2 clients.
- Recall "safety" notifications documented as the only cap-exempt category.
- All ten animations behind `animPassV3` and Reduce-Motion compliant.
