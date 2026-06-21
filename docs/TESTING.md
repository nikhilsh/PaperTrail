# Testing PaperTrail

## What runs today

Every PR (and master push) runs **`ios sim build + unit tests`** via
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) — a no-signing
simulator build plus the `PaperTrailTests` suite on the newest available iOS
runtime, mirroring the conduit ios-build CI strategy. The check is **required**
by branch protection (strict mode: branches must also be up to date with
master), so nothing merges without green tests.

The suite is pure-logic + SwiftData-in-memory; it needs no signing, no
network, and no iCloud account.

| File | Covers |
|---|---|
| `ExtractionLogicTests` | amount parsing, total picking, table/text price overlays, plausible-product filter, merchant hint strength |
| `ColumnPriceFillTests` | anchored column-major price fill (the Gain City shape) + its no-fill safety gates |
| `ReceiptFixtureTests` | golden receipt fixtures: date/UEN ground truth, hallucination grounding, table reconstruction |
| `RoomAndDateTests` | date conventions/parsing, room suggestions |
| `TrustModelTests` | PurchaseRecord trust-field migration defaults + round-trip, ReminderSettings |
| `TrustFeatureTests` | Export CSV (escaping, trust fields), Claim Packet PDF (doc number, rendered page), avatar initials, honest backup states |
| `FMSeamTests` | Foundation Models seam (see below) + gated real-model smoke test |
| `ProductMemoryLearningTests` | item-level learning staleness (hintStrength gate) |

### Adding a golden receipt fixture

Append a `Fixture` to `ReceiptFixtureTests.allFixtures` with the flattened OCR
text, ground-truth date/UEN/total/line items, and any amounts the model has
hallucinated for that receipt. Every fixture is automatically exercised by all
four fixture tests — this is the cheapest way to turn a field bug report into
a permanent regression guard (capture the transcript from the Sentry
`extraction.*` events).

## Testing Foundation Models

**The on-device model cannot run in CI.** Foundation Models in the Simulator
require the *host* Mac to run macOS 26 with Apple Intelligence enabled;
GitHub's macOS runners satisfy neither, so `SystemLanguageModel.default`
reports unavailable there. Strategy:

1. **Seam tests (CI-safe, run everywhere).** `ExtractionPipeline` takes its
   extractors via the `FieldExtractionService` protocol, so `FMSeamTests`
   drives the full pipeline with stub FM/heuristic results and verifies the
   behavior the app depends on: FM values win, heuristics fill gaps, the
   larger amount is preferred, FM line items beat heuristic ones, empty FM
   falls back wholesale. This is how "FM behavior" stays regression-guarded
   on every PR.
2. **Real-model smoke test (gated).**
   `FMSeamTests.realFoundationModelExtractsSampleReceipt` is
   `.enabled(if:)`-gated on actual model availability: skipped on CI,
   exercised automatically when the suite runs on a Mac with macOS 26 + Apple
   Intelligence (or a device). Run locally via Xcode's test action — no flag
   needed.
3. **On-device diagnostics.** Settings → Advanced & Diagnostics → *Test
   Foundation Models* runs a real plain-text + `@Generable` extraction on the
   device and prints the raw result — the manual check for model/runtime
   issues CI can't see.

## What unit tests deliberately don't cover

UI/layout, VisionKit scanning, CloudKit sync + CKShare, notifications
delivery, and the live FM runtime are **on-device concerns** — CI green means
"compiles + logic holds", per CLAUDE.md. Flag changes touching those paths as
*needs on-device verification* and use the Sentry breadcrumbs/events
(`extraction.*`, `cloud.image`, `cloudkit.preflight`) to make failures
self-diagnosing.
