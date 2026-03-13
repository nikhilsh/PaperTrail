# OCR Notes

## Recommendation
Use Apple's native stack first:
- `VisionKit` for document scanning
- `Vision` (`VNRecognizeTextRequest`) for OCR

## Why
- best integration with iOS simulator/device workflows
- no extra dependency weight
- no SPM package needed for the first useful version
- easier privacy story for on-device receipt scanning
- avoids premature lock-in to a third-party OCR wrapper

## Decision
Do **not** add a third-party OCR SPM package yet.

Instead:
1. keep `OCRService` as the app boundary
2. implement a native `VisionOCRService` next
3. add scanning via `VisionKit` when Capture becomes real

## When to reconsider third-party OCR
Only if native Vision proves weak for:
- multilingual receipts we care about
- structured field extraction quality
- device performance constraints
- maintenance burden from handwritten wrappers

For now, native Apple OCR is the right call.
