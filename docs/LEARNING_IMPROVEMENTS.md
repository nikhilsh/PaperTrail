# Improving PaperTrail's Training & Learning Loop

Research notes + roadmap (2026-06). Builds on the shipped learning system; see
`EXTRACTION_ARCHITECTURE.md` for the pipeline itself.

## The loop today (what already works)

1. **Capture** — on every save, `CorrectionLogger` diffs extraction vs. the
   user's final values across 7 fields → JSONL on disk + a
   `LearningFeedbackPayload` callback; per-field outcomes (kept / corrected /
   filled-blank) go to Sentry as non-PII breadcrumbs (`ExtractionMetrics`).
2. **Store** — `MerchantLearningService.captureFeedback` upserts a
   `MerchantProfile` (keyed by normalized UEN, falling back to fuzzy name
   match): aliases, default category/currency/warranty, inferred
   amount/date/product hints, correction count, recency. Item-level
   `ProductCategoryMemory` maps normalized product → category.
3. **Feed back** — learned merchant names amplify Vision OCR
   (`customWords`); merchant hints seed the FM prompt with
   `hintStrength`-dependent phrasing (trust strongly ≥0.6 / use unless text
   disagrees / defer); the heuristic path falls back to learned
   currency/category/warranty; the Review UI auto-applies category, currency,
   and warranty when confidence ≥0.3.
4. **Decay** — `MerchantProfile.hintStrength` = evidence (saturates ~10
   corrections, 70%) + recency (~6-month exponential decay, 30%). As of this
   change, `ProductCategoryMemory.hintStrength` mirrors it (saturates ~5,
   60/40) and `productCategorySuggestion` gates on ≥0.25 — a stale one-off no
   longer mislabels forever. ✅ shipped with this doc

## Ranked improvement roadmap

### Near-term (high value, low risk)

1. ✅ *(shipped, PR #45)* **Feed the stored hints to the heuristic path.** `amountHint`, `dateHint`,
   `productHint` are inferred and stored per merchant but only the FM prompt
   reads them. The heuristic extractor (which runs on every scan, and is the
   *only* path when Apple Intelligence is off) could use them to bias its
   total-picking and date-format resolution. Cheap, deterministic, unit-testable.
2. **Grow the golden fixture suite from field failures.** The Sentry
   `price_debug` / `structured_empty` events carry real device transcripts;
   each new failure should become a `ReceiptFixtureTests` fixture
   (anonymized) so the fix is regression-guarded in CI forever. The
   column-major Gain City receipt is the template — `ColumnPriceFillTests`
   was built exactly this way. Make this the standard bug-fix workflow.
3. ✅ *(shipped, PR #45)* **Use learned `documentKinds`.** Captured per merchant, never read. Bias
   the document-kind classifier with the merchant's history (a Gain City scan
   is near-certainly a sales order) — improves kind-dependent extraction
   phrasing and FM instructions.
4. ✅ *(shipped, PR #46 — Diagnostics "Learning" card + Copy-diagnostics section)* **Read the corrections JSONL.** It's currently write-only. A lightweight
   on-device summary (per-field correction rates by merchant/source) could:
   (a) drive an "extraction health" line in Diagnostics, (b) auto-tune when
   to trust FM vs heuristic per merchant, (c) be exportable for offline eval.

### Medium-term

5. ✅ *(shipped, PR #47 — 2 examples max, values clipped)* **Per-merchant few-shot in the FM prompt.** Beyond hints, include 1–2 of
   the user's *actual past corrections* for this merchant as input→output
   examples ("for this store, the total appears as 'Total amount due'"). This
   is the strongest "training" available without touching model weights —
   prompt-level adaptation, instantly reversible, no shipping cost. Guard the
   context window (the FM context-overflow failure of 2026-06-04 — chunk or
   summarize examples).
6. ◐ *(merchant aliasing already existed via SemanticMatcher; product-side fuzzy match also present)* **Embedding-based product memory.** `ProductCategoryMemory` already fuzzy
   matches via `SemanticMatcher`; extend the same embedding store to merchant
   aliasing (replacing the 0.82-threshold name fuzz) and to "similar past
   product → warranty length" suggestions.
7. **Eval harness in CI as a quality gate.** Once fixtures number in the
   dozens, compute field-level accuracy over the suite per PR and fail on
   regression (a scorecard test, not just pass/fail assertions).

### Long-term: actually training the model

8. **Foundation Models LoRA adapter.** Apple ships an
   [adapter training toolkit](https://developer.apple.com/apple-intelligence/foundation-models-adapter/)
   (Python, LoRA): train on receipt-extraction examples, export an
   `.fmadapter`, ship via Background Assets, load with
   `SystemLanguageModel(adapter:)`. Realistic notes for us:
   - **Cost:** ~160 MB per adapter version; requires Account Holder
     entitlement approval; training runs offline (Mac/GPU, Jupyter samples
     provided).
   - **Maintenance trap:** an adapter is bound to a *specific base-model
     version* — every OS model update requires retraining. Apple's own
     guidance: prefer prompting + guided generation unless they've plateaued.
   - **Verdict:** revisit only after (1)–(5) plateau and we have a few
     hundred curated transcript→fields pairs from the corrections log. The
     corrections JSONL is already accumulating exactly the right training
     data — keep capturing.

## Cross-user learning: using other users' data (research, 2026-06)

Today every device learns alone. The unlock is recognizing **which layer of
the learned data is personal**:

| Tier | Examples | Shareable? |
|---|---|---|
| **Merchant facts** | normalized name, aliases, UEN, document kind, date convention, total-label phrasing ("Total amount due"), default currency, support phone | **Yes** — facts about businesses, identical for every user |
| **Product facts** | product → category, product → typical warranty length | Mostly — products are public objects (screen for free-text leakage) |
| **Personal data** | amounts, purchase dates, transcripts, names/addresses | **Never** leaves the device raw |

`MerchantProfile` is, by construction, almost entirely Tier-1 — the learning
system was accidentally designed for sharing. Mechanisms, in deployment order:

1. **Seed pack (zero infra, do anytime).** Curate merchant profiles (own
   data + public knowledge) into a bundled/remote JSON the app merges as
   *community-confidence* priors. Hostable on the existing Fyra site next to
   the OTA assets; refresh without app updates. New users get a warm start
   for SG retailers on day one.
2. **CloudKit public database community directory (no server).** The app's
   existing container has a public DB every user can read and opt-in write.
   One `CommunityMerchant` record type keyed by UEN (fallback: normalized
   name), holding only Tier-1 fields plus contributor counts. Devices
   contribute their merchant-level hints (never correction values); readers
   aggregate. Required safeguards:
   - **Min-N before trust**: a community hint counts only with ≥3 independent
     contributors agreeing (majority vote per field) — poisoning resistance.
   - **Precedence**: personal `hintStrength` always outranks community
     confidence; community hints cap at the "tentative" prompt phrasing.
   - **Opt-in consent**: a "Help improve PaperTrail for everyone" toggle
     (off by default; PDPA/GDPR-clean since only merchant facts are shared,
     but consent + App Store privacy label updates regardless).
   - Kill-switch flag, recency decay, and rate limits per contributor.
3. **Backend aggregation (rides the receipts-inbox backend).** When the
   `receipts@in.papertrail.app` service exists, the same backend can accept
   opt-in merchant aggregates, curate centrally (human review), and publish
   a signed community pack via CDN — better moderation than a raw public DB.
4. **The shared model IS the cross-user vehicle (LoRA).** With explicit
   opt-in donation of anonymized transcript→fields pairs, train ONE adapter
   centrally and ship it to everyone via Background Assets. Other users'
   receipts improve your extraction without any user data being visible to
   any other user — the cleanest end-state, gated on item 8's economics.
5. **Already happening, weakly:** the non-PII Sentry breadcrumbs (field
   outcomes per source/kind) aggregate across all installs today. Reading
   them developer-side to decide which extractor weakness to fix next *is*
   cross-user learning — no new consent needed since no values are sent.

**Sequencing for PaperTrail's reality (a handful of users today):** start
with (1) + (5) now; build (2) when there's a real user base to feed it;
(3)/(4) ride the inbox backend and adapter decisions respectively.

### Implemented (2026-06): Supabase majority-learning pipeline — no curation

Product decisions superseding the sketch above: **opt-IN** (default OFF; a
first-launch "Help improve extraction?" prompt plus Settings → Your data →
"Share anonymous learning data" — see `CommunityLearning.swift:38` and
`AppShellView`), **no human curation
anywhere** — aggregation is pure SQL — and aggressive-but-anonymized
collection (structured field corrections; never transcripts, images, or
identity).

- **Client** (`CommunityLearning.swift`): every locally-logged correction is
  also POSTed to Supabase (PostgREST, anon key) keyed by a random install
  UUID — generated locally, never linked to Apple ID/iCloud. Values are
  scrubbed (emails/phone-shaped runs → `[redacted]`) and capped at 120 chars
  client-side, 200 server-side. On launch the app pulls the aggregated
  `community_merchants` table (cached on disk) and uses it as the learning
  context **only when no personal profile exists**, confidence capped at
  0.45 — community knowledge is never authoritative.
- **Backend** (`supabase/schema.sql`, paste-and-go): `correction_events`
  (RLS: anon may INSERT only — raw rows are unreadable from devices) and
  `community_merchants` (anon may SELECT only). The "ML" is
  `refresh_community_merchants()` on pg_cron hourly: `mode()` per merchant
  per fact across a 12-month window, published only at **≥3 distinct
  installs** (majority learning + poisoning resistance); raw events expire
  after 18 months. The same `correction_events` table doubles as the
  LoRA-adapter training corpus (CSV export) when item 8 matures.
- **Ops**: secrets `SUPABASE_URL`/`SUPABASE_ANON_KEY` injected into
  `GeneratedSecrets.swift` by CI (dormant when absent);
  `supabase-keepalive.yml` pings twice weekly because free-tier projects
  pause after ~1 week idle.
- **Tool choice**: Supabase free tier (500 MB Postgres, unlimited API
  requests, pg_cron) over PocketBase-on-Fyra (no pause, but hand-rolled
  aggregation + another service to run) and Cloudflare D1 (no pg_cron
  equivalent without Workers code). Revisit if the pause/500 MB ever bind.
- **One manual step**: create the free Supabase project, paste
  `supabase/schema.sql`, add the two repo secrets. Everything else is live.

## Privacy guardrails

All per-user learning stays on-device (SwiftData + JSONL); Sentry gets field
*names* and outcomes, never values. Any fixture lifted from a real transcript
must be anonymized (names/addresses/phones) before committing — see
`ReceiptFixtureTests` conventions. Any future cross-user sharing is opt-in
and limited to the Tier-1/Tier-2 columns above — correction *values* never
leave the device except as an explicit, separately-consented data donation
for adapter training.
