# PaperTrail docs

Reference and planning docs for PaperTrail. Operating principles for agents live in
[`../CLAUDE.md`](../CLAUDE.md); the project overview is in [`../README.md`](../README.md).

## Product & domain
- [SPEC.md](SPEC.md) — product and technical spec
- [DOMAIN_MODEL.md](DOMAIN_MODEL.md) — domain entities (`PurchaseRecord`, `Attachment`)
- [DECISIONS.md](DECISIONS.md) — important decisions and rationale (dated)
- [SCREEN_FLOW.md](SCREEN_FLOW.md) — screen-by-screen navigation flow

## Architecture
- [ARCHITECTURE.md](ARCHITECTURE.md) — stack, layering, and principles
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) — folder layout and naming guidance
- [EXTRACTION_ARCHITECTURE.md](EXTRACTION_ARCHITECTURE.md) — OCR → Foundation Models extraction pipeline
- [OCR_NOTES.md](OCR_NOTES.md) — OCR direction and constraints
- [AI-EXTRACTION-RESEARCH.md](AI-EXTRACTION-RESEARCH.md) — research & roadmap for improving extraction

## Planning & status
- [PROJECT_STATE.md](PROJECT_STATE.md) — current state snapshot
- [ROADMAP.md](ROADMAP.md) — staged direction
- [MILESTONES.md](MILESTONES.md) — milestone plan
- [MILESTONE_1_CHECKLIST.md](MILESTONE_1_CHECKLIST.md) — milestone 1 checklist
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) — implementation plan
- [BACKLOG.md](BACKLOG.md) — near-term tasks

## Ops & setup
- [XCODE_SETUP.md](XCODE_SETUP.md) — local Xcode project setup
- [OTA_DISTRIBUTION.md](OTA_DISTRIBUTION.md) — GitHub Actions Ad Hoc OTA setup
- [SENTRY_DSYM_QUICK_START.md](SENTRY_DSYM_QUICK_START.md) — Sentry dSYM upload quick start
- [SENTRY_DSYM_SETUP.md](SENTRY_DSYM_SETUP.md) — Sentry dSYM upload full setup

> Some planning/status docs predate recent changes (e.g. OTA hosting moved off GitHub
> Pages). Treat dated snapshots as point-in-time; `CLAUDE.md` reflects current working rules.
