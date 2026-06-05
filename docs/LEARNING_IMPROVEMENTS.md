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

1. **Feed the stored hints to the heuristic path.** `amountHint`, `dateHint`,
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
3. **Use learned `documentKinds`.** Captured per merchant, never read. Bias
   the document-kind classifier with the merchant's history (a Gain City scan
   is near-certainly a sales order) — improves kind-dependent extraction
   phrasing and FM instructions.
4. **Read the corrections JSONL.** It's currently write-only. A lightweight
   on-device summary (per-field correction rates by merchant/source) could:
   (a) drive an "extraction health" line in Diagnostics, (b) auto-tune when
   to trust FM vs heuristic per merchant, (c) be exportable for offline eval.

### Medium-term

5. **Per-merchant few-shot in the FM prompt.** Beyond hints, include 1–2 of
   the user's *actual past corrections* for this merchant as input→output
   examples ("for this store, the total appears as 'Total amount due'"). This
   is the strongest "training" available without touching model weights —
   prompt-level adaptation, instantly reversible, no shipping cost. Guard the
   context window (the FM context-overflow failure of 2026-06-04 — chunk or
   summarize examples).
6. **Embedding-based product memory.** `ProductCategoryMemory` already fuzzy
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

## Privacy guardrails (unchanged)

All learning stays on-device (SwiftData + JSONL); Sentry gets field *names*
and outcomes, never values. Any fixture lifted from a real transcript must be
anonymized (names/addresses/phones) before committing — see
`ReceiptFixtureTests` conventions.
