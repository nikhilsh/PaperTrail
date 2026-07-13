# Household Sharing Architecture (Milestone 4)

Real cross-account record sharing: household members on different Apple IDs see and
edit the same purchase records, live. This document is the design of record; the
roadmap's older "hybrid Core Data" sketch (docs/ROADMAP.md, Milestone 4) is
superseded by the decision below.

## Decision: CKSyncEngine beside SwiftData (2026-07-13, approved by Nik)

SwiftData has **no native CKShare support** as of iOS 26 / WWDC 2026
(`ModelConfiguration.CloudKitDatabase` = `automatic | none | private(_:)` only;
confirmed against Apple's live docs, WWDC25/26 changelogs, and Apple DTS forum
statements through 2026-03). Three options were evaluated:

| Option | Verdict |
|---|---|
| Hybrid Core Data (`NSPersistentCloudKitContainer` second stack) | **Rejected.** Both frameworks emit `CD_<Entity>` record types and write private sync to the same `com.apple.coredata.cloudkit.zone`; dual-framework use of one container is undocumented, collision-prone, and Apple DTS's steer is that adopting Core Data for sharing pulls the whole synced graph into Core Data eventually. |
| Full Core Data migration | **Rejected for now.** Cleanest sharing story per DTS, but rewrites the load-bearing persistence layer (CLAUDE.md: high-risk, only verifiable on-device) before any sharing ships. |
| **Manual CKShare + CKSyncEngine beside SwiftData** | **Chosen.** First-party sync scheduling (iOS 17+), zero changes to the SwiftData store, and it matches patterns already in the app: `Attachment` links via `recordID` (no persisted relationships), images already sync as raw `CKAsset`s outside SwiftData (`CloudImageSyncManager`), and `HouseholdManager` already does raw-CloudKit `CKShare` work. Cost: we own record mapping and conflict merge. |

## Topology

```
                    iCloud.nikhilsh.PaperTrail
 ┌──────────────────────────────┐   ┌───────────────────────────────┐
 │ OWNER (private database)     │   │ MEMBER (shared database)      │
 │                              │   │                               │
 │ com.apple.coredata.cloudkit. │   │  HouseholdZone (owner's,      │
 │ zone ← SwiftData private     │   │  visible via zone-wide        │
 │ sync, UNTOUCHED              │   │  CKShare)                     │
 │                              │   │                               │
 │ HouseholdZone (custom zone)  │   │  CKSyncEngine(sharedCloudDB)  │
 │  ├ cloudkit.share (zone-wide)│   │        │                      │
 │  ├ SharedPurchaseRecord*     │   │        ▼                      │
 │  ├ SharedAttachment*         │   │  HouseholdCache (local,       │
 │  CKSyncEngine(privateCloudDB)│   │  NOT the SwiftData store)     │
 └──────────────────────────────┘   └───────────────────────────────┘
```

- **`HouseholdZone`**: one custom record zone in the owner's private database.
  Shared **zone-wide** via `CKShare(recordZoneID:)` — every record in the zone is
  visible to every household participant. This matches household semantics and
  avoids per-record `parent` hierarchies. (A zone supports exactly one zone-wide
  share; records inside it cannot also carry record shares.)
- **Record types** (ours to name — no `CD_` prefix, no collision with SwiftData's
  generated types): `SharedPurchaseRecord`, `SharedAttachment`. Fields mirror the
  SwiftData models 1:1 (see `SharedRecordMapper`). Images ride as a `CKAsset`
  field on `SharedAttachment` (Phase 4), mirroring the existing `ImageAsset`
  pattern but inside the zone so participants can fetch them.
- **The SwiftData store is never touched.** Own records stay in SwiftData;
  sharing a record *mirrors* it into `HouseholdZone`. Records shared *to* us land
  in a local **`HouseholdCache`** (JSON file store under Application Support,
  loaded into an `@Observable` model at launch), NOT the CloudKit-backed
  SwiftData store — inserting them there would re-upload them to the member's own
  private database and duplicate the data.

## Sync engines

Two `CKSyncEngine` instances owned by `HouseholdSyncEngine` (new,
`PaperTrail/HouseholdSync/`):

- **Private engine** (`container.privateCloudDatabase`) — owner side. Sends local
  mirror writes to `HouseholdZone`, fetches edits made by members (members write
  into the owner's zone through the shared database; the owner sees them as
  private-DB zone changes).
- **Shared engine** (`container.sharedCloudDatabase`) — member side. Fetches the
  owner's zone into `HouseholdCache`, sends the member's edits back.

Both engines persist their `CKSyncEngine.State.Serialization` (from
`.stateUpdate` events) to disk so sync resumes incrementally across launches.
Push notifications are handled by CKSyncEngine automatically; we additionally
call `fetchChanges()` on foreground as a poll fallback (community consensus:
CloudKit pushes are best-effort).

**Conflict strategy (v1): server wins, then re-apply pending local edit.** On
`.serverRecordChanged`, take the server record, overlay any still-pending local
field changes, re-queue. Field-level merge is deliberately out of scope until
device testing shows it's needed; `updatedAt` is carried on every record for
diagnostics.

## Share lifecycle

- **Create**: `HouseholdManager.makeShare()` changes from sharing the decoy
  `Household` root record to saving `CKShare(recordZoneID: HouseholdZone.id)`.
  The decoy `household-root` record and its share are deleted on first
  zone-share creation (the flag has been off; no production participants exist).
  Roster UI (`HouseholdView`) keeps reading `share.participants`.
- **Accept**: requires `INFOPLIST_KEY_CKSharingSupported = YES` (missing today)
  and a share-acceptance hook (the app has no app/scene delegate). Phase 2 adds a
  minimal `UIApplicationDelegateAdaptor` whose
  `application(_:configurationForConnecting:options:)` installs a scene delegate
  implementing `windowScene(_:userDidAcceptCloudKitShareWith:)` →
  `container.accept(metadata)` → start the shared engine.
- **Leave/stop**: member removes self via `UICloudSharingController`; owner
  stopping sharing deletes the zone share. Local mirrors/caches are purged on
  departure events (`.fetchedDatabaseChanges` zone deletions).

## What gets shared

The existing `@AppStorage("household.shareWholeLibrary")` toggle becomes real:
ON mirrors every record; OFF mirrors only records marked shared (per-record
toggle in record detail, Phase 3). Mirroring is one `PurchaseRecord` +
its `Attachment` metadata; image assets follow in Phase 4.

## Feature flag

`HouseholdManager.recordSharingEnabled` stays the master switch, still a
compile-time `static let` and still `false` until each phase is device-verified.
All new code paths check it; the decoy-share behavior remains the fallback so
`HouseholdView` keeps working unchanged when the flag is off.

## Coexistence

- `.papertrail` single-record export (`RecordSharingManager`) and bulk export
  (`ExportService`) are untouched — one-shot send remains useful outside a
  household.
- `CloudImageSyncManager` (private-DB `ImageAsset` records) is untouched; shared
  images are a separate `CKAsset` field on `SharedAttachment` (Phase 4).
- SwiftData CloudKit sync config, schema, and entitlement are untouched. The only
  container-level addition is one custom zone + our own record types, which
  CloudKit namespaces away from `CD_*`.

## Phases (one PR each, CI-green, flag off)

1. **Foundation** — `HouseholdSync/` module: zone management, `SharedRecordMapper`
   (model ⇄ CKRecord, unit-tested), `HouseholdCache`, `HouseholdSyncEngine`
   skeleton with both engines + state persistence + Sentry (`category:
   "cloud.sharing"`). No UI change.
2. **Share plumbing** — zone-wide share creation in `HouseholdManager`, decoy
   migration, `CKSharingSupported`, delegate chain for share acceptance,
   member-side engine start.
3. **UI** — per-record share toggle, whole-library toggle wiring, "Shared with
   me" Library section, shared-record detail (read/edit), ownership badges.
4. **Images + hardening** — `CKAsset` images on `SharedAttachment`, conflict
   polish, departure cleanup, Sentry breadcrumb sweep, device-verification
   checklist.

## On-device verification checklist (per phase; CI only proves compilation)

- [ ] P1: zone created idempotently; mapper round-trips a real record; engines
      start and persist state; no impact on existing SwiftData sync.
- [ ] P2: invite from device A → accept on device B (different Apple ID) → B's
      shared DB sees `HouseholdZone`; decoy share cleanly replaced.
- [ ] P3: record shared on A appears on B; edit on B appears on A; unshare
      removes from B.
- [ ] P4: images visible on B; conflict (simultaneous edit) resolves without
      data loss; member leaving purges local cache.
