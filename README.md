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
- `SPEC.md` — product and technical spec
- `ARCHITECTURE.md` — implementation direction
- `MILESTONES.md` — staged build plan
- `BACKLOG.md` — near-term tasks
- `DECISIONS.md` — important decisions and rationale
- `OCR_NOTES.md` — OCR direction and constraints
