# PaperTrail

PaperTrail is an iOS app for keeping track of the devices you own, the purchase proof behind them, their warranty status, and the support path when something breaks.

## Core promise
Know what you own, whether it is still covered, and what to do next.

## Product direction
- SwiftUI
- device-centric organization
- OCR-assisted capture
- strong local search
- iCloud durability via CloudKit-backed sync
- support/warranty context attached to each device record

## Current status
Project initialized and now has a working local shell, in-memory create/edit flow, and simulator-tested build loop.

## Immediate goal
Build a disciplined v1 that proves the core loop:
1. capture receipt/warranty proof
2. turn it into a useful device record
3. show warranty status clearly
4. make retrieval/support actions easy later

## Docs
All reference and planning docs live in [`docs/`](docs/README.md). Highlights:
- [`docs/SPEC.md`](docs/SPEC.md) — product and technical spec
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — implementation direction
- [`docs/EXTRACTION_ARCHITECTURE.md`](docs/EXTRACTION_ARCHITECTURE.md) — OCR → extraction pipeline
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — important decisions and rationale
- [`docs/OTA_DISTRIBUTION.md`](docs/OTA_DISTRIBUTION.md) — GitHub Actions + Ad Hoc OTA setup notes

Agent operating principles are in [`CLAUDE.md`](CLAUDE.md).
