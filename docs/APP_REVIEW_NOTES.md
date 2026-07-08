# App Review Notes — PaperTrail v1.0

PaperTrail is a home inventory app for purchases, receipts, and warranties. **All core functionality works without any account, sign-in, or server dependency** — there is nothing to log into and no demo account is needed.

## Testing the core flow
1. Open the app → tap **+** → **Scan Document** (camera permission prompt appears).
2. Scan any paper receipt or invoice — any store receipt works.
3. The app runs OCR on-device (Apple Vision) and pre-fills fields: merchant, product, date, amount, warranty. On devices with Apple Intelligence enabled, an on-device language model (Apple FoundationModels framework) improves extraction; on all other devices a deterministic parser is used automatically. **No extraction data ever leaves the device**, and no functionality is lost without Apple Intelligence.
4. Save — the record appears in the Library with a warranty status badge.

Alternative to the camera: **Import Photos** brings in an existing receipt image from the photo library.

## Data & privacy
- No accounts exist. Records and images are stored on-device and synced via the user's **private iCloud (CloudKit)** database, which the developer cannot access.
- Two optional, anonymized data flows, both controllable in Settings:
  - Crash/error reporting (Sentry).
  - "Community learning": when the user corrects an extracted field, the correction string may be shared **only after explicit opt-in consent** (first-launch prompt), keyed by a random install UUID — no account, device, or iCloud identifiers.
- Warranty reminders use local notifications only.
- The camera is used solely for document scanning (VisionKit document camera).
