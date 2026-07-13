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
CloudKit pushes are best-effort). **See "Before the flag flips" below — push
notifications are not actually wired up yet**, so today this poll fallback is
the *only* way either engine learns about changes.

The private engine's fetches are scoped to `HouseholdZone` alone
(`nextFetchChangesOptions` returns `.zoneIDs([HouseholdSchema.ownerZoneID])`).
The private database also contains SwiftData's own
`com.apple.coredata.cloudkit.zone` — without this scoping, the private
engine's first fetch would download the entire `CD_*` SwiftData mirror into
its own change-tracking state, alongside the actual household data it cares
about. The shared engine has no such neighbor (it only ever sees zones
explicitly shared to this account), so it fetches everything (`.all`).

**Sends rebuild their `CKRecord` from SwiftData at send time, not from a
queued snapshot.** `mirror(dto:)`/`unshare(id:)` only queue a record ID with
`CKSyncEngine.state` (which CloudKit already persists durably across a
relaunch); they do not stash the DTO content anywhere. When the engine
actually asks for a batch to send (`nextRecordZoneChangeBatch`),
`pendingRecord(for:)` re-fetches the live `PurchaseRecord`/`Attachment` from
SwiftData by id and builds the outgoing `CKRecord` from *that*. Two failure
modes this avoids: (1) an in-memory "pending DTO" map would silently lose the
write if the app relaunched between queueing and sending — CKSyncEngine's own
persisted pending-change list would still ask for the record, but the DTO
content behind it would be gone; (2) a save confirmation for an older edit
(v1) can never clobber a newer, still-queued edit (v2), because there's no
stale snapshot sitting in a map to be cleared out by the v1 confirmation —
the next send just re-reads SwiftData's current state. `pendingRecord(for:)`
returns `nil` when the local record has since been deleted (the deletion hook
already queued a `.deleteRecord` for it instead — see "Deletion" below), so a
now-stale `.saveRecord` pending change sends nothing.

**Confirmation-time cache truth, with rollback on terminal failure.** On
`.sentRecordZoneChanges`, a `savedRecords` entry is parsed back into a DTO and
upserted into `HouseholdCache` right there — the cache reflects what CloudKit
actually confirmed, not an earlier optimistic write that a later edit might
have superseded. A `failedRecordSaves` entry that isn't a
`.serverRecordChanged` conflict (i.e. a terminal failure) rolls the
optimistic cache entry back out (parsed by UUID from the record name) so the
record looks unmirrored again and the next reconcile retries it, rather than
the cache silently believing a write succeeded that never did.
`failedRecordDeletes` is re-queued once per record name per launch, but only
when the local SwiftData record genuinely no longer exists — otherwise
something raced and re-queuing the delete would be actively wrong.

**Conflict strategy (v1): server wins, then re-apply pending local edit.** On
`.serverRecordChanged`, take the server record, overlay any still-pending local
field changes, re-queue onto the *originating* engine (private or shared —
whichever the event came from). If the error carries no server record to
re-apply onto, log and stop rather than re-queuing into a conflict loop.
Field-level merge is deliberately out of scope until device testing shows
it's needed; `updatedAt` is carried on every record for diagnostics.

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
  departure events (`.fetchedDatabaseChanges` zone deletions) — but ONLY when
  the deleted zone is actually `HouseholdZone`; the private database also
  contains SwiftData's own `com.apple.coredata.cloudkit.zone`, and a deletion
  notification for that (or any other unrelated zone) must never purge this
  cache. Other zones' deletions are logged and ignored.
- **Dual-role guard**: a device can be a household OWNER or a household
  MEMBER, never both. `makeZoneShare()` checks for an existing shared-in zone
  share first and refuses to create an owned share if one exists — without
  this, a member creating their own household and a background `refresh()`
  race could wipe the shared-in cache out from under them.
- **Account change**: on `.accountChange`, `HouseholdSyncEngine` tears down
  BOTH engines entirely (not just their cache/state files) and rebuilds them
  via `start()`, and tells `HouseholdManager` to clear its cached
  share/roster (`resetForAccountChange()`). Leaving the old engine objects
  alive after an account switch meant their next `.stateUpdate` would write
  the OLD account's serialization right back to disk.

## What gets shared

The existing `@AppStorage("household.shareWholeLibrary")` toggle becomes real:
ON mirrors every record; OFF mirrors only records marked shared (per-record
toggle in record detail, Phase 3). Mirroring is one `PurchaseRecord` +
its `Attachment` metadata; image assets follow in Phase 4.

**The whole-library policy itself is zone-resident, not per-device.** A
per-device `UserDefaults` toggle alone would leak: if the owner sets
selective sharing on device A, device B's own local default (`true`) would
silently start mirroring the whole library the next time device B reconciles
— an *un-consented* share. A singleton `HouseholdSettings` record
(`household-settings`, no id suffix — one per zone) carries the real,
zone-wide policy; `HouseholdCache.shareWholeLibrarySetting: Bool?` mirrors it
locally, and `HouseholdMirrorCoordinator.effectiveShareWholeLibrary()` is
what reconcile actually uses:
- settings record has arrived (`shareWholeLibrarySetting` non-nil) →
  authoritative, full stop.
- no settings record yet, cache empty → brand-new share, safe to fall back to
  this device's own local toggle.
- no settings record yet, cache non-empty → some other device has state this
  one hasn't fetched — default to **not** auto-mirroring new records rather
  than guessing, since guessing "on" could re-share something another device
  deliberately narrowed.

The settings record isn't DTO-backed like purchase records/attachments —
`HouseholdSyncEngine.mirrorSettings(shareWholeLibrary:)` just queues the
write, and `pendingRecord(for:)` builds its content from `UserDefaults`'s
current value at send time (via
`HouseholdMirrorCoordinator.localShareWholeLibraryDefault()`), same
always-current durability story as the DTO-backed sends. `makeZoneShare()`
seeds the settings record immediately after creating a brand-new share, so
a second owner device never has to guess from an empty cache.

**The zone is the source of truth for "is this record shared?"** — no flag is
persisted on `PurchaseRecord` (no schema change to the load-bearing store). A
record is shared iff its mirror exists in `HouseholdZone`; the owner's own
`HouseholdCache` (fed by the private engine fetching the zone) answers the
question locally, and multiple owner devices converge automatically.

**Mirroring is reconcile-based, not write-path-based.** A
`HouseholdMirrorCoordinator` listens for `ModelContext.didSave` and app
foreground, diffs SwiftData records against the cache's view of the zone, and
queues mirror deltas — a couple of call sites instead of hooking every save
path in the UI. Reconcile fetches SwiftData with a real `do`/`catch`, not
`(try? ...) ?? []`: a fetch *failure* must never be treated as an empty
library — it just aborts that reconcile pass and lets the next trigger retry.

**Deletion requires positive evidence — it is never inferred from the
reconcile diff.** `computeDiff` produces upserts only (`Diff` has no delete
fields). Earlier revisions treated "present in the cache but absent from the
local SwiftData fetch" as "the owner deleted it" and queued an unshare for
the whole set — but that's indistinguishable from a partial/empty local
library: a second owner device before its first sync, a fresh reinstall, or a
transient `context.fetch` error all look exactly like "deleted everything,"
and would mass-unshare the entire household zone. Deletion instead flows
through two explicit hooks on `HouseholdMirrorCoordinator`,
`recordDeleted(recordID:attachmentIDs:)` and `attachmentDeleted(id:)`, called
directly from the app's actual delete call sites
(`RecordDetailView.deleteRecord()`, `LibraryView.deleteRecord(_:)`) — a real
`modelContext.delete` is the only evidence that ever removes a mirror from
`HouseholdZone`.

**Members are read-only in v1.** The `CKShare` still grants `.allowReadWrite`
(so no re-invite later), but member-side editing UI ships in a later phase —
shared-in records render via a dedicated read-only detail view, never through
`EditRecordView` (which edits SwiftData models).

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
4. **Images + hardening** — images ride as a `CKAsset` field (`asset`) on
   `SharedAttachment`. The owner's own private engine skips re-downloading
   originals it already has on disk (`Documents/Attachments/<localFilename>`);
   `HouseholdCache` stores everyone else's copies under its own `images/`
   directory, keyed by attachment id. `SharedRecordDetailView` shows a
   thumbnail once the asset lands, and a "syncing" caption fallback per
   attachment until then. Also: zone-save/delete failure logging
   (`.sentDatabaseChanges`), stuck-queue diagnostics in
   `nextRecordZoneChangeBatch`. Conflict polish and departure cleanup remain
   open for device testing.

## Before the flag flips — required setup

**Push notifications are not configured.** There is no `aps-environment`
entitlement and no `remote-notification` background mode in this app today —
CKSyncEngine never receives a silent push telling it something changed. In
practice this means sync currently only happens on app launch/foreground (the
`fetchChanges()` poll fallback in `HouseholdMirrorCoordinator`'s foreground
observer and `PaperTrailApp`'s launch `.task`) — a household member could sit
in a backgrounded app for an hour and see nothing new until they bring it
forward. Before `HouseholdManager.recordSharingEnabled` flips to `true` for
real users, Nik needs to:
1. Add the **Push Notifications** capability in the Apple Developer portal
   for the app ID.
2. Add the `aps-environment` entitlement and the `remote-notification`
   background mode to the app's entitlements/Info.plist.
3. Regenerate the Ad Hoc provisioning profile to include the new
   capability — see the team-ID mismatch warning in
   [`docs/OTA_DISTRIBUTION.md`](OTA_DISTRIBUTION.md) before touching signing.

This is **deliberately not done in this PR** — entitlement changes risk
breaking Ad Hoc signing/distribution, and the flag is still `false`, so there
are no real users depending on push-driven sync yet.

**Known cost, not yet optimized:** shared images double iCloud storage — an
attachment's `CKAsset` lives once as `ImageAsset` (private, via
`CloudImageSyncManager`) and again as the `asset` field on `SharedAttachment`
(inside `HouseholdZone`, Phase 4) — and a metadata-only attachment edit
(e.g. just the OCR text) re-uploads the full JPEG on the next mirror, because
`SharedRecordMapper.apply(_:to:assetFileURL:)` has no way to send metadata
without resending whatever asset accompanies it in the same `CKRecord` save.

## On-device verification checklist (per phase; CI only proves compilation)

- [ ] P1: zone created idempotently; mapper round-trips a real record; engines
      start and persist state; no impact on existing SwiftData sync.
- [ ] P2: invite from device A → accept on device B (different Apple ID) → B's
      shared DB sees `HouseholdZone`; decoy share cleanly replaced.
- [ ] P3: record shared on A appears on B; edit on B appears on A; unshare
      removes from B.
- [ ] P4: images visible on B; conflict (simultaneous edit) resolves without
      data loss; member leaving purges local cache.
