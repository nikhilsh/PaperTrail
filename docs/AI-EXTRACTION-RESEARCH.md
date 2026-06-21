# Improving PaperTrail's AI Extraction — Research & Roadmap

_Last updated: 2026-06-03 · Scope: on-device, Apple-native, privacy-preserving_

This document is the synthesis of deep research into how PaperTrail can capture
OCR better, categorize and recognize items more reliably, and whether (and how)
we should train Apple Foundation Models. It is grounded in our **current
pipeline** and Apple's iOS 26 capabilities, and ends with a prioritized roadmap.

The guiding constraint stays the same as the rest of the app: **everything
on-device, nothing leaves the phone, prefer blank over bad.**

---

## 1. Where we are today

The current capture → structured-record flow:

```
VNDocumentCameraViewController        ← user scans (multi-page capable)
        │  UIImage(s)
        ▼
VisionOCRService.performRecognition   ← VNRecognizeTextRequest
        │  .recognitionLevel = .accurate
        │  .usesLanguageCorrection = true
        │  raw text = lines joined by "\n"   ← STRUCTURE IS DISCARDED HERE
        ▼
ExtractionPipeline.extract            ← runs both extractors concurrently
        ├── FoundationModelExtractionService   (@Generable ReceiptExtractionSchema)
        │      • availability gate, OCR-text cleaning, 3-attempt locale retry
        │      • guided generation → typed fields + lineItems
        └── HeuristicFieldExtractor            (regex / keyword, deliberately conservative)
               • brand list, model-number regex, company-suffix scan
               • quality gates: boilerplate/junk/stopword rejection
        ▼
   merge(): prefer FM value per field; for amount prefer the LARGER value
        ▼
StructuredExtractionResult  →  DraftRecordView (per-field confidence tags)
        ▼
   user edits  →  MerchantLearningService.captureFeedback
        ▼
   MerchantProfile (SwiftData, keyed on normalizeMerchantName)
        • defaultCategory, currency, warranty months, amount/date/product hints
        • correctionCount; fed back as learningContext on the NEXT scan
```

Key source files:

| Concern | File |
| --- | --- |
| Vision OCR | `PaperTrail/OCRService.swift` |
| Pipeline + merge | `PaperTrail/ExtractionPipeline.swift` |
| FM schema + heuristics | `PaperTrail/FoundationModelExtractor.swift` |
| Learning loop | `PaperTrail/ExtractionLearning.swift` |
| Result types / confidence | `PaperTrail/OCRExtractionResult.swift` |

### What's already good

- **Guided generation done right.** We use `@Generable` + `@Guide` so the model
  emits a typed `ReceiptExtractionSchema` via constrained decoding — no JSON
  parsing, no "the model returned prose" failures. This is exactly Apple's
  recommended path (WWDC25 "Deep dive into Foundation Models").
- **Graceful degradation.** FM and heuristics run concurrently; the heuristic
  path always works so the app is functional on devices without Apple
  Intelligence, in unsupported regions, or before the model asset downloads.
- **A real learning loop.** Every user correction updates a `MerchantProfile`,
  which is injected as hints on the next scan from the same merchant.
- **"Prefer blank over bad"** is enforced with aggressive quality gates and
  per-field confidence surfaced in the UI.

### Weak points the research targets

1. **OCR throws away document structure.** We flatten Vision output to newline-
   joined text, losing bounding boxes, reading order, and table/column layout —
   the single biggest lever (see §2).
2. **No custom vocabulary.** Vision has no `customWords` / brand lexicon, so
   model numbers and store names get mangled.
3. **Categorization is shallow.** Category comes only from the FM guess or a
   learned `defaultCategory` — there's no semantic understanding of the item.
4. **Merchant matching is exact-normalized only.** `normalizeMerchantName`
   won't unify "Harvey Norman" vs "HARVEY NORMAN (Suntec)" robustly; OCR
   variance fragments the learning loop.
5. **Hints are static strings.** No temporal decay, no confidence weighting on
   `correctionCount`, no item-level learning.

---

## 2. OCR: the biggest, cheapest wins (iOS 26)

### 2.1 Adopt `RecognizeDocumentsRequest` (the headline change)

iOS 26 ships a new Vision API, `RecognizeDocumentsRequest`, that returns a
**structured `DocumentObservation`** instead of flat text lines. It exposes:

- **Tables** — rows/cells with their text, so a receipt's item × price columns
  arrive already aligned instead of as interleaved lines.
- **Lists**, **paragraphs**, and **reading order**.
- **Detected data** — dates, prices, URLs, phone numbers, addresses surfaced as
  typed entities directly from Vision.

Why this matters for us: today the FM and heuristics have to *reconstruct*
"which number is the grand total" and "which line is an item vs a footer" from a
flattened blob (it's literally why `merge()` has a `pickLargerAmount` hack and
why the heuristic has pages of boilerplate filters). With table structure, line
items and totals become a structural read rather than a guess.

**Action:** add a `DocumentStructureOCRService` that calls
`RecognizeDocumentsRequest`, and feed both (a) the structured tables/entities and
(b) a structure-aware text serialization into the pipeline. Keep
`VisionOCRService` as the fallback for older inputs. Source: WWDC25 "Read
documents using the Vision framework" (session 272); `RecognizeDocumentsRequest`
/ `DocumentObservation` docs.

### 2.2 Give Vision a custom vocabulary

`VNRecognizeTextRequest` supports `customWords` and we pass none. Receipts are
full of brand and model tokens that the language model "corrects" into nonsense.

**Action:** seed `customWords` with our existing `knownBrands` /
`knownShortBrands` sets (already in `FoundationModelExtractor.swift`) plus
merchant names we've learned from `MerchantProfile`. Cheap, immediate accuracy
win on exactly the fields users correct most.

### 2.3 Use structured entities before regex

Vision's detected dates/prices/addresses are more reliable than our hand-rolled
`NSDataDetector` + regex passes. Prefer Vision's typed entities for date and
amount; fall back to heuristics only when absent. This shrinks the most
brittle part of `HeuristicFieldExtractor`.

### 2.4 Capture-time quality

Most extraction failures are really *capture* failures (glare, skew, crop).
`VNDocumentCameraViewController` already does edge detection and perspective
correction — confirm we use its corrected output, and consider a lightweight
pre-OCR check (resolution / contrast) that nudges the user to rescan before we
ever hit the model.

---

## 3. Categorization & item recognition

Three complementary, all-on-device options, cheapest first:

### 3.1 Keep + strengthen FM categorization (now)

The `@Guide` for `category` currently hard-codes a 9-value list. Good, but:

- **Categorize from line items, not just the headline.** Once §2.1 gives us
  clean line items, ask the model to classify each item's `kind` and category.
  This is the "decompose the task" guidance from WWDC25 286 — smaller, well-
  scoped prompts beat one mega-prompt.
- **Constrain harder.** Use `@Guide(.anyOf([...]))` to force the category enum
  instead of describing it in prose, so the model can't invent "Gadgets".

### 3.2 Add an embedding-based categorizer (medium term)

Apple's Natural Language framework (`NLEmbedding` / `NLContextualEmbedding`,
and `NLModel` for classification) can map a product name to a category vector
**fully on-device**. Two uses:

- **Fuzzy merchant matching** (fixes weak point #4): embed merchant strings and
  match by cosine similarity, so OCR variants of the same store collapse into
  one `MerchantProfile`. This single fix makes the whole learning loop converge
  faster.
- **Category suggestion** that generalizes beyond merchants we've seen — embed
  the product name, nearest-neighbour against category exemplars.

### 3.3 Create ML custom classifier (if §3.1/§3.2 plateau)

If categorization still misses, a **Create ML text classifier** trained on
(product name → category) pairs ships as a small `.mlmodel`, runs on-device, and
needs **no Foundation Models version coupling** (see §4 for why that matters).
This is the recommended path over LoRA for pure classification: smaller, faster,
independently versioned, and trainable from our own correction data.

---

## 4. Should we train Foundation Models? (LoRA adapters)

**Short answer: not yet — and probably not for most of what we want.**

### What's actually possible

Apple ships a **Foundation Models adapter training toolkit** (the
`foundation-models-adapter` Python package). You *can* train a **LoRA adapter**
on the on-device base model:

- Requires an Apple-silicon Mac (32GB+) or a Linux CUDA GPU, Python 3.11+.
- Apple themselves ship example adapters (e.g. a content-tagging adapter),
  proving the path works.
- Produces a small adapter that specializes the base model for a narrow task.

### The catch that makes it a poor default

> **Every adapter is bound to one specific base-model version.** When Apple
> updates the on-device model (which happens with OS updates), the adapter
> stops loading and **must be retrained.**

For a small team this is a recurring maintenance tax with no warning schedule.
You'd be signing up to re-run training and re-ship every time iOS bumps the
model — or risk the feature silently breaking. Apple's own guidance (WWDC25 286
and the adapter docs) is explicit: **reach for prompt engineering, schema
constraints (`@Guide`), and the learning loop first;** only train an adapter
when the task is *narrow, high-value, and not achievable via prompting.*

### Decision

| Goal | Recommended approach |
| --- | --- |
| Better field extraction | Prompt + `@Guide` tightening + structured OCR (§2) |
| Better categorization | FM guided gen → `NLModel`/embeddings → Create ML (§3) |
| Domain vocabulary | Vision `customWords` + learning loop (§2.2) |
| Merchant-specific behavior | Strengthen `MerchantProfile` loop (§5) |
| A genuinely narrow, high-value, un-promptable task | _Then_ consider a LoRA adapter — and budget for retraining on every model update |

In other words: **we already have the right architecture.** The wins are in
feeding the model better input (structured OCR) and a smarter learning loop —
not in training weights we'd have to babysit.

### Design for the on-device model's shape

The on-device model is ~3B params, 2-bit quantized, ~1GB of OS storage, fully
offline. Practical implications we should honor:

- **Decompose** receipt processing into focused sub-prompts (classify doc kind →
  extract header fields → classify line items) rather than one giant call.
- Keep prompts/instructions tight; the model has a limited context budget.
- Never assume it's available — the concurrent heuristic fallback stays.

---

## 5. Strengthen the correction-driven learning loop

This is our highest-leverage *proprietary* asset — every correction makes the
app better and the data never leaves the device. Improvements:

1. **Fuzzy merchant keys** (see §3.2) so corrections aggregate instead of
   fragmenting across OCR variants.
2. **Confidence-weight by `correctionCount`.** A merchant corrected 10× should
   produce near-authoritative hints; a 1× correction should be a gentle nudge.
3. **Temporal decay / recency.** Stores change layout, price bands drift; weight
   recent corrections higher than year-old ones.
4. **Item-level learning.** Today we learn merchant→category; also learn
   product→category (e.g. "AirPods" → Electronics) independent of where bought.
5. **Promote hints into Vision.** Learned merchant/product tokens become
   `customWords` (closes the loop between §2.2 and §5).

---

## 6. Prioritized roadmap

Ordered by **(impact ÷ effort)**, on-device throughout.

### Phase 1 — OCR structure & vocabulary (highest ROI, low risk)
- [ ] `DocumentStructureOCRService` using `RecognizeDocumentsRequest`; feed
      tables + typed entities into the pipeline (`OCRService.swift`,
      `ExtractionPipeline.swift`).
- [ ] Pass `customWords` (brands + learned merchants) to Vision (§2.2).
- [ ] Prefer Vision's typed date/amount entities over regex (§2.3).
- [ ] Drop `pickLargerAmount` guesswork once the total is structurally known.

### Phase 2 — Learning loop & matching
- [ ] Fuzzy merchant matching via `NLEmbedding` cosine similarity (§3.2).
- [ ] Confidence-weight + recency-decay hints by `correctionCount` (§5).
- [ ] Item-level (product→category) learning (§5.4).

### Phase 3 — Categorization depth
- [ ] Per-line-item classification with tightened `@Guide(.anyOf)` (§3.1).
- [ ] Embedding-based category suggestion for unseen products (§3.2).
- [ ] _If still short:_ Create ML text classifier from accumulated corrections
      (§3.3).

### Phase 4 — Only if a narrow, high-value gap remains
- [ ] Evaluate a LoRA adapter for that one task, **with an explicit retraining
      plan tied to OS/model updates** (§4). Default answer remains "no".

### Always-on
- [ ] Keep the heuristic fallback and "prefer blank over bad" invariant.
- [ ] Keep extraction diagnostics flowing to Sentry to measure each change.

---

## 7. How we'll measure it

We already emit `ExtractionDiagnostics` breadcrumbs to Sentry (FM availability,
field counts, rejected fields, source). Before Phase 1, add lightweight,
privacy-safe counters so we can prove each change helps:

- Per-field **correction rate** (how often the user edits each field) — the
  truest accuracy signal, and it's already implicit in `captureFeedback`.
- FM-vs-heuristic **source mix** and FM availability by device.
- Line-item count and "amount needed override" rate (should fall after Phase 1).

Ship each phase behind these metrics; a change that doesn't move correction
rate down isn't worth the maintenance.

---

## Sources

- WWDC25 286 — _Deep dive into the Foundation Models framework_
- WWDC25 301 — _Bring on-device AI to your app with Foundation Models_
- WWDC25 272 — _Read documents using the Vision framework_
  (`RecognizeDocumentsRequest`, `DocumentObservation`)
- Apple Developer docs — `VNRecognizeTextRequest` (`customWords`,
  `usesLanguageCorrection`), Natural Language (`NLModel`, `NLEmbedding`,
  `NLContextualEmbedding`), Create ML text classifiers
- Apple `foundation-models-adapter` training toolkit + adapter docs
- machinelearning.apple.com — 2025 on-device model updates
