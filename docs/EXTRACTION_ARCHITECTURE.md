# PaperTrail — OCR + Foundation Models Extraction Architecture

> Goal: turn noisy scanned purchase documents into reliable, reviewable structured data without making the app feel brittle or magical in the bad way.

## Product goal
PaperTrail should not merely read text.
It should help the user go from:
- scanned proof document
- to an accurate, mostly pre-filled record

The important word is **accurate**.
Not all fields should be filled at all costs. When uncertain, PaperTrail should prefer:
- partial autofill
- visible uncertainty
- fast user review

over confident nonsense.

---

## Core principle
Use a **hybrid extraction pipeline**:

1. deterministic OCR for raw text
2. on-device Foundation Models for semantic field extraction
3. heuristic/rule validation for sanity checks and fallback
4. human review for uncertain fields
5. correction logging for iterative improvement

The model should help understand the document.
It should not be the only source of truth.

---

## Pipeline overview

### Stage 1 — Capture and cleanup
Input source:
- VisionKit document scan
- camera photo fallback
- photo library import

Responsibilities:
- detect/crop pages
- normalize orientation
- preserve page order
- optionally improve contrast / readability

Output:
- one or more cleaned page images

### Stage 2 — Raw OCR
Use Vision OCR only for text extraction.

Responsibilities:
- extract all text faithfully
- preserve line grouping where possible
- keep page boundaries
- do not infer semantics here

Output:
- full recognized text
- optional line/box structure
- per-page OCR text

This should remain deterministic and debuggable.

### Stage 3 — Document classification
Before detailed field extraction, classify the document.

Suggested values:
- `receipt`
- `invoice`
- `warranty_card`
- `order_confirmation`
- `packing_slip`
- `support_document`
- `manual`
- `unknown`

Why:
- a supermarket receipt and warranty card should not be parsed with the same assumptions
- downstream extraction can use document-specific logic

Output:
- `documentKind`
- `documentKindConfidence`
- optional explanation (internal/debug only)

### Stage 4 — Structured extraction
Run Foundation Models on the OCR text to extract candidate structured fields.

This should use guided/structured generation only.
No freeform prose.

Suggested field groups:

#### Merchant / source
- merchant name
- vendor / seller
- support provider
- website / email / phone if clearly present

#### Purchase details
- product name
- product model / SKU
- purchase date
- order number / receipt number
- amount subtotal / tax / total
- currency

#### Warranty / coverage
- explicit warranty duration
- inferred warranty duration (only if text strongly suggests it)
- warranty expiry date
- policy/coverage notes

#### Filing helpers
- suggested category
- suggested attachment type
- suggested title / summary

Each field should be returned as:
- value
- confidence
- source

### Stage 5 — Heuristic validation and gap filling
Apply deterministic rules after the model returns its candidates.

Use heuristics to:
- validate date plausibility
- validate amount format
- normalize currency codes/symbols
- reject impossible warranty values
- cross-check total/subtotal/tax when present
- fill obvious missing fields from regex/pattern extraction

Rules should be able to:
- accept model output
- downgrade confidence
- replace with heuristic result
- leave blank when uncertain

### Stage 6 — Merge into extraction result
The app should merge the best available output into a single structured result.

Priority model:
1. high-confidence Foundation Models result
2. validated heuristic result
3. medium-confidence Foundation Models result
4. user review required / blank

Output should still remain reviewable and explainable enough for debugging.

---

## Data model recommendations

## Document kind
Add explicit document classification to extraction result.

```swift
DocumentKind
- receipt
- invoice
- warrantyCard
- orderConfirmation
- packingSlip
- supportDocument
- unknown
```

## Confidence model
Every extracted field should carry confidence.

```swift
enum ExtractionConfidence {
    case high
    case medium
    case heuristic
    case low
    case none
}
```

## Source model
Track where the value came from.

```swift
enum ExtractionSource {
    case foundationModel
    case heuristic
    case merged
    case user
}
```

## Field wrapper

```swift
struct ExtractedField<T> {
    var value: T?
    var confidence: ExtractionConfidence
    var source: ExtractionSource
}
```

This enables better UI and future analytics.

---

## UI behavior recommendations

## Autofill behavior
Not all fields should behave the same.

### High confidence
- fill automatically
- no warning needed

### Medium confidence
- fill automatically
- visually indicate that it was inferred

### Low confidence
- suggest, but do not silently commit where risk is high
- prefer placeholder or inline suggestion UI

### None
- leave blank

## Review UX
Draft/edit screen should make uncertainty obvious but lightweight.

Suggested cues:
- subtle badges like:
  - `Verified`
  - `Needs review`
  - `Suggested`
- “Extracted with Apple Intelligence” only when true
- optional per-field hint later if needed

The goal is not to show AI internals.
The goal is to make review fast.

## Important product rule
If PaperTrail is uncertain, it should be humble.
A blank field is better than a wrong receipt amount or false warranty.

---

## Foundation Models prompt strategy

## Role
The model should be prompted as a strict extraction engine, not a chat assistant.

Prompt qualities:
- prefer literal facts from OCR text
- never invent values
- return null when unsure
- distinguish merchant from product
- do not assume warranty unless explicitly indicated
- be concise and structured only

## Suggested pass structure
For best quality, use multiple conceptual passes even if implemented within one orchestrator.

### Pass A — classify document
What kind of document is this?

### Pass B — extract purchase fields
Merchant, date, totals, product, identifiers.

### Pass C — extract warranty/support fields
Warranty duration, expiry clues, support contact, policy text.

Even if this is collapsed into one pipeline for v1, the architecture should preserve this separation conceptually.

---

## Fallback strategy
Foundation Models should improve extraction, not become a single point of failure.

Fallback cases:
- device does not support Apple Intelligence / Foundation Models
- model unavailable
- low confidence or invalid structured output
- simulator/unsupported environment

Fallback behavior:
- use heuristic extraction only
- keep existing OCR result flow working
- mark extraction source appropriately

This matters for resilience and backward compatibility during bring-up.

---

## Correction logging and learning loop
Do not jump to custom ML yet.
First, collect signal.

When the user edits autofilled fields, log:
- original extracted value
- corrected value
- field name
- source (`foundationModel` / `heuristic` / `merged`)
- document kind
- confidence level

This can later answer:
- which fields are most often wrong?
- which merchants confuse the extractor?
- where do heuristics outperform the model?
- where should merchant-specific parsing be added?

This is what “ML-ready” should mean first: measurement and correction data.

---

## Proof-image considerations
PaperTrail now separates:
- metadata sync
- proof image sync via CKAsset

Extraction should be attached to the OCR/metadata path, not to image-sync transport itself.

Meaning:
- images are proof assets
- OCR text and extracted fields are semantic data
- edits/corrections should update the semantic layer without re-uploading proof files unnecessarily

---

## Recommended implementation order

### Phase 1 — current/foundation
- deterministic OCR stays in place
- Foundation Models structured extractor exists
- heuristic fallback exists
- merge pipeline exists

### Phase 2 — improve field quality
- add document kind classification
- add more explicit field confidence handling in UI
- add better warranty extraction rules
- improve merchant/product disambiguation

### Phase 3 — review UX
- per-field uncertainty badges
- “needs review” experience in DraftRecordView
- correction-aware save flow

### Phase 4 — analytics / learning
- correction logging
- aggregate extraction quality metrics
- merchant-specific parsing hints

### Phase 5 — optional future ML work
Only after enough real correction data exists:
- custom classification
- merchant templates
- specialized extraction strategies

---

## Product decisions to hold firmly
- Do not invent fields.
- Do not over-autofill low-confidence values.
- Keep the OCR stage deterministic.
- Keep the model structured.
- Keep fallback behavior intact.
- Treat user correction as valuable training signal.

---

## Immediate next build goals
1. Confirm the Foundation Models extraction layer compiles and ships on iOS 26 build.
2. Test real receipts/invoices for:
   - merchant
   - product name
   - purchase date
   - amount/currency
   - category
   - warranty duration
3. Compare Foundation Models results vs heuristic-only fallback on a few representative documents.
4. Improve DraftRecordView review cues so uncertainty is visible without clutter.
