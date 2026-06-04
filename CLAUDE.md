# CLAUDE.md

Operating principles for Claude agents working in this repo.

| Principle              | Problem It Solves                                       | The One-Liner                                                |
|------------------------|---------------------------------------------------------|--------------------------------------------------------------|
| Think Before Coding    | Wrong assumptions, hidden confusion, missing tradeoffs  | Don't assume. Don't hide confusion. Surface tradeoffs.       |
| Simplicity First       | Overcomplication, bloated abstractions                  | Minimum code that solves the problem. Nothing speculative.   |
| Surgical Changes       | Orthogonal edits, touching code you shouldn't           | Touch only what you must. Clean up only your own mess.       |
| Goal-Driven Execution  | Vague plans with no verification                        | Define success criteria. Loop until verified.                |

## What PaperTrail is

iOS app (SwiftUI, **iOS 26+**) for tracking devices you own, the purchase proof
behind them, warranty status, and the support path when something breaks.
Scan → OCR → extract fields → save → search → get reminded before warranty expires.
Product spec and direction live in [`docs/`](docs/README.md) (start with
[`docs/SPEC.md`](docs/SPEC.md) and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)).

## Working in this repo

**iOS is CI-compile-only on the dev box.** There is no Mac/Xcode on the machine
agents run on — the project builds **only** via Xcode (no `Package.swift`/`Makefile`),
so local builds are impossible. App changes are verified **only by CI**
(`.github/workflows/ios-adhoc-ota.yml`), which archives and exports an Ad Hoc `.ipa`.
**CI green means it COMPILES — NOT that the UI/runtime behaves.** Flag any
UI / layout / OCR / extraction / sync fix as **"needs on-device verification"** and
don't claim it's fixed until Nik confirms on a device. Batch one OTA release per
device-test session.

**Instrument anything that can fail with Sentry.** Because on-device failures are
otherwise invisible (CI-compile-only), capture errors and leave breadcrumbs at each
meaningful step of any flow that can fail — scan, OCR, extraction, CloudKit
sync/preflight, image upload/download, Sign in with Apple. Sentry runs in OTA builds;
dSYM upload is wired into CI so traces symbolicate. The goal: the next crash is
self-diagnosing from Sentry without a device. Setup: [`docs/SENTRY_DSYM_QUICK_START.md`](docs/SENTRY_DSYM_QUICK_START.md).

**CloudKit + SwiftData architecture is load-bearing — don't casually change it.**
What makes sync work (see [`docs/PROJECT_STATE.md`](docs/PROJECT_STATE.md)):
- A single CloudKit-backed SwiftData store.
- **No persisted SwiftData `@Relationship`** between `PurchaseRecord` and `Attachment`
  — `Attachment` links via `recordID`.
- **No image blobs in SwiftData** — images live on disk (`ImageStorageManager`) and
  sync separately as `CKAsset`s (`CloudImageSyncManager`, `ImageAsset` record type).
- **Macro-safe stored-property defaults** on SwiftData models.
Changing model schema or relationships risks a CloudKit migration break that's only
visible on-device. Treat schema edits as high-risk and call them out explicitly.

**Extraction degrades gracefully — never crash if Apple Intelligence is absent.**
The pipeline runs `FoundationModelExtractionService` (on-device LLM, `@Generable`)
and `HeuristicExtractionService` concurrently; FM values win, heuristics fill gaps.
Guard FM with `#if canImport(FoundationModels)` + runtime availability checks. The
heuristic path must always work. Details: [`docs/EXTRACTION_ARCHITECTURE.md`](docs/EXTRACTION_ARCHITECTURE.md).

**Releases / OTA** are driven by the rolling release tag `adhoc-latest` via
`.github/workflows/ios-adhoc-ota.yml`. Bump `CFBundleVersion` so devices see an
update. Ad Hoc installs require each device UDID in the provisioning profile.
There is a known **team-ID mismatch** documented in
[`docs/OTA_DISTRIBUTION.md`](docs/OTA_DISTRIBUTION.md) — check it before touching signing.

**Key identifiers:**
- Repo: `github.com/nikhilsh/PaperTrail` — default branch `master`
- Bundle ID: `nikhilsh.PaperTrail` · iCloud container: `iCloud.nikhilsh.PaperTrail`

**Commit style:** a tight subject line plus a body explaining *what changed and why*
when the change isn't trivial; note tests touched. End the commit with the
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer.
Open changes as PRs against `master` (normal flow) — don't push straight to it.
