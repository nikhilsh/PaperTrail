# OCR Notes

## Architecture (as of iOS 26 migration)

### Two-layer extraction pipeline

1. **Vision OCR** (`VNRecognizeTextRequest`) — converts scanned images to raw text. This is unchanged.
2. **Field extraction pipeline** (`ExtractionPipeline`) — takes raw OCR text and extracts structured fields:
   - **Primary**: Apple Foundation Models on-device LLM (iOS 26+, Apple Intelligence required)
   - **Fallback**: Regex/heuristic extraction (always available, no model dependency)

### Why this design

- Foundation Models provides dramatically better field extraction than regex — it understands context, handles messy OCR output, and can infer categories.
- But Foundation Models requires Apple Intelligence, which isn't available on all devices or regions.
- The heuristic fallback ensures the app works everywhere iOS 26 runs.
- Both run concurrently; the pipeline merges results (FM values preferred, heuristics fill gaps).

## Key types

| Type | Purpose |
|------|---------|
| `VisionOCRService` | Vision framework OCR → raw text → ExtractionPipeline |
| `ExtractionPipeline` | Orchestrator: FM + heuristic, merge, bridge to `OCRExtractionResult` |
| `FoundationModelExtractionService` | On-device LLM structured extraction via `@Generable` |
| `HeuristicExtractionService` | Regex/pattern fallback (migrated from original `VisionOCRService`) |
| `ReceiptExtractionSchema` | `@Generable` struct defining the JSON schema the model outputs |
| `StructuredExtractionResult` | Per-field values with confidence levels |
| `OCRExtractionResult` | Legacy bridge type consumed by views |

## Confidence levels

Each extracted field carries an `ExtractionConfidence`:
- `.high` — Foundation Model returned the field confidently
- `.medium` — Foundation Model returned it but with less certainty (e.g. warranty duration)
- `.heuristic` — came from regex/pattern matching
- `.none` — field could not be extracted

## Foundation Models integration details

- Framework: `FoundationModels` (iOS 26+)
- Entry point: `LanguageModelSession`
- Availability check: `LanguageModelSession.isAvailable` (runtime guard)
- Structured output: `session.respond(to:generating:)` with `@Generable` schema
- System prompt instructs the model to parse receipt/warranty OCR text
- `#if canImport(FoundationModels)` used for compile-time safety
- Schema uses `@Guide` annotations to describe expected field semantics

## When to reconsider

- If Foundation Models quality is poor for certain receipt types, consider adding receipt-type-specific prompts
- If a third-party service offers better extraction for specific document types, the `FieldExtractionService` protocol makes it pluggable
- The heuristic layer can be removed once Foundation Models coverage is sufficient

## Original recommendation (preserved)

Use Apple's native stack:
- `VisionKit` for document scanning
- `Vision` (`VNRecognizeTextRequest`) for OCR
- `FoundationModels` for intelligent field extraction

No third-party OCR dependencies.
