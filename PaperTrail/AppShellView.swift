import SwiftUI
import SwiftData
import CoreSpotlight

// MARK: - Tabs

enum AppTab: Hashable {
    case library
    case warranty
    case search
    case settings
}

// MARK: - Routes

/// Every place outside normal in-app navigation that can ask PaperTrail to
/// jump somewhere: a `papertrail://` deep link, a tapped notification, a
/// Home Screen quick action, a Spotlight search result, or an App Intent.
/// All of them funnel through `AppRouter.navigate(to:)` so there's one
/// choke point to log from and one place to extend.
enum Route: Hashable {
    case record(UUID)
    case capture
    case expiringSoon
}

extension Route {
    /// Parses a `papertrail://` URL. Recognized forms:
    /// `papertrail://record/<uuid>`, `papertrail://capture`,
    /// `papertrail://expiring`. Returns `nil` for anything else, including a
    /// malformed or missing UUID on a `record` link.
    init?(url: URL) {
        guard url.scheme == "papertrail" else { return nil }
        switch url.host {
        case "capture":
            self = .capture
        case "expiring":
            self = .expiringSoon
        case "record":
            guard let uuidString = url.pathComponents.dropFirst().first,
                  let uuid = UUID(uuidString: uuidString) else { return nil }
            self = .record(uuid)
        default:
            return nil
        }
    }
}

/// Shared navigation state so any screen — or any non-view entry point
/// (notifications, quick actions, Spotlight, App Intents) — can deep-link
/// into the app. `.shared` is the single instance: it's created before
/// `AppShellView` necessarily exists (an App Intent can set a pending route
/// while the app is still launching), so every caller reads/writes the same
/// object rather than one scoped to a view's lifetime.
@Observable
@MainActor
final class AppRouter {
    static let shared = AppRouter()

    var selectedTab: AppTab = .library
    var showCapture = false
    /// The v3 "five ways to shelve" paper sheet (`addSheetV2`, §3 of
    /// `docs/design-v3/V3_BRIEF.md`). Flag-gated at the FAB tap site; when the
    /// flag is off the FAB goes straight to `showCapture` exactly as in v2.
    var showAddSheet = false

    /// A record to push onto the Library tab's stack, consumed by
    /// `navigationDestination(item:)` in `AppShellView`.
    var pendingRecordID: UUID?

    /// A document handed to PaperTrail via Mail/Files "Open in PaperTrail",
    /// already run through extraction — consumed by a full-screen cover that
    /// presents the same review screen a manual scan would.
    var pendingImportPayload: DraftPayload?

    /// Cross-entry-point in-flight guard for import. Two importers can race
    /// to both pass their `pendingImportPayload == nil` guard — Mail/Files
    /// "Open in PaperTrail" (`AppShellView.importIncomingFile`) and the
    /// share-extension drain (`ShareInboxDrain`) — and then both try to
    /// assign `pendingImportPayload`. Each import path checks this
    /// synchronously at its own entry, before any `await`, and sets it
    /// before doing any work; it's cleared in a `defer` once that import
    /// concludes (success or failure).
    var isImporting = false

    /// True while a full-screen cover (scan, import review) is presented or
    /// about to be. `SoftAskCoordinator` checks this before ever presenting
    /// the notification soft-ask — nothing may interrupt an in-progress scan
    /// or import (V2_BRIEF §4 acceptance criteria).
    var hasActiveCover: Bool { showCapture || pendingImportPayload != nil || isImporting || showAddSheet }

    func navigate(to route: Route) {
        switch route {
        case .record(let id):
            pendingRecordID = id
            selectedTab = .library
        case .capture:
            showCapture = true
        case .expiringSoon:
            selectedTab = .warranty
        }
        AppLogger.info("Routed to \(route)", category: "deeplink")
    }
}

// MARK: - Foreground refresh coalescing

/// Coalesces `DigestScheduler.reschedule` and `WidgetSnapshotWriter.write`
/// behind one ~1.5s debounce, mirroring `SpotlightIndexer.reindexAllDebounced`.
/// Each of those used to run its own full `PurchaseRecord` fetch off the
/// same app-foreground hook — two fetches per foreground, and rapid
/// foreground/background flips (e.g. a quick app-switcher peek) used to
/// repeat both. This does exactly one fetch per debounce firing and feeds
/// both consumers from it. `SpotlightIndexer` and `ShareInboxDrain` are
/// deliberately not included here: Spotlight has its own independent
/// debounce, and the share-inbox drain must run promptly on every
/// foreground, not sit behind a delay.
@MainActor
private enum ForegroundRefreshCoordinator {
    private static var task: Task<Void, Never>?
    private static let debounceInterval: Duration = .seconds(1.5)

    static func scheduleDebounced(modelContext: ModelContext) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            let records: [PurchaseRecord]
            do {
                records = try modelContext.fetch(FetchDescriptor<PurchaseRecord>())
            } catch {
                AppLogger.error("Foreground refresh fetch failed: \(error.localizedDescription)", category: "app")
                return
            }
            DigestScheduler.reschedule(records: records)
            WidgetSnapshotWriter.write(records: records)
            // Soft-ask retry (N1): catches the initial ask if it was skipped
            // earlier because a scan/import cover was still up, otherwise
            // tries the one allowed re-ask. No-ops instantly otherwise.
            await SoftAskCoordinator.shared.retrySoftAsk(records: records)
        }
    }
}

// MARK: - Shell

struct AppShellView: View {
    @State private var router = AppRouter.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("community.consentPrompted") private var communityConsentPrompted = false
    @AppStorage(CommunityLearning.optOutKey) private var communityLearningEnabled = false
    @State private var showLearningConsent = false

    var body: some View {
        @Bindable var router = router

        ZStack(alignment: .bottom) {
            // Active tab content. Each destination keeps its own NavigationStack.
            Group {
                switch router.selectedTab {
                case .library:
                    NavigationStack {
                        LibraryView()
                            .navigationDestination(item: $router.pendingRecordID) { recordID in
                                RecordDetailByIDView(recordID: recordID)
                            }
                    }
                case .warranty:
                    NavigationStack { WarrantyView() }
                case .search:
                    NavigationStack { SearchView() }
                case .settings:
                    NavigationStack { SettingsView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PTTabBar(
                selection: $router.selectedTab,
                onCapture: {
                    // v3 §3 "five ways to shelve": flag on → the paper add
                    // sheet; flag off → straight to capture, exactly as v2.
                    if FeatureFlags.isOn(.addSheetV2) {
                        router.showAddSheet = true
                    } else {
                        router.showCapture = true
                    }
                }
            )
        }
        .background(PT.inkCanvas.ignoresSafeArea())
        .environment(router)
        .preferredColorScheme(.dark)
        .tint(PT.gold)
        .softAskPresentation()
        .addSheetV2Presentation()
        .fullScreenCover(isPresented: $router.showCapture) {
            NavigationStack {
                CaptureView()
            }
            .tint(PT.gold)
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $router.pendingImportPayload) { payload in
            NavigationStack {
                DraftRecordView(seedType: payload.type, seededAttachments: payload.attachments, seededOCR: payload.ocr, seedsProductImage: payload.seedsProductImage)
            }
            .tint(PT.gold)
            .preferredColorScheme(.dark)
        }
        .onAppear {
            if !communityConsentPrompted {
                showLearningConsent = true
            }
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let uniqueID = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let recordID = UUID(uuidString: uniqueID) else {
                AppLogger.warn("Spotlight activity missing/invalid identifier", category: "deeplink")
                return
            }
            router.navigate(to: .record(recordID))
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                SpotlightIndexer.reindexAllDebounced()
                ForegroundRefreshCoordinator.scheduleDebounced(modelContext: modelContext)
                // Not debounced with the above — a share-sheet import is
                // something the user is actively waiting on, so it must run
                // promptly on every foreground, not coalesced behind a delay.
                ShareInboxDrain.drainIfPossible(modelContext: modelContext)
            }
        }
        .onChange(of: router.selectedTab) { _, newTab in
            // A deep-linked/notification/Spotlight-tapped record push shouldn't
            // ghost-reappear if the user leaves the Library tab and comes back.
            if newTab != .library {
                router.pendingRecordID = nil
            }
        }
        .onChange(of: router.showCapture) { wasShowing, isShowing in
            // The common first-save path is Capture → DraftRecordView, and
            // saving only pops DraftRecordView off Capture's own nav stack —
            // `showCapture` itself stays true until the user closes Capture,
            // well past `SoftAskCoordinator`'s save-time attempt. Catch it
            // here instead, the moment Capture actually closes.
            if wasShowing, !isShowing { retrySoftAskIfNeeded() }
        }
        .onChange(of: router.pendingImportPayload) { wasPresented, isPresented in
            if wasPresented != nil, isPresented == nil { retrySoftAskIfNeeded() }
        }
        .alert("Help improve extraction?", isPresented: $showLearningConsent) {
            Button("Share anonymously") {
                communityLearningEnabled = true
                communityConsentPrompted = true
            }
            Button("Not now", role: .cancel) {
                communityConsentPrompted = true
            }
        } message: {
            Text("When you correct a scanned field, PaperTrail can share that correction anonymously (no account, no identifiers, a random install ID only) to improve extraction for everyone. You can change this anytime in Settings.")
        }
    }

    // MARK: Soft-ask (N1)

    /// Re-evaluates the soft-ask right after a full-screen cover (Capture,
    /// import review) finishes closing back to the app root — see
    /// `SoftAskCoordinator.retrySoftAsk` for why this matters beyond the
    /// save-time attempt. One-off fetch, cheap and infrequent (fires only on
    /// a cover-close transition).
    private func retrySoftAskIfNeeded() {
        guard let records = try? modelContext.fetch(FetchDescriptor<PurchaseRecord>()) else { return }
        Task { await SoftAskCoordinator.shared.retrySoftAsk(records: records) }
    }

    // MARK: Deep links

    private func handleOpenURL(_ url: URL) {
        if url.isFileURL {
            guard router.pendingImportPayload == nil else {
                AppLogger.warn("Import ignored — another import is in review", category: "import")
                return
            }
            AppLogger.info("Incoming file: \(fileDescription(for: url))", category: "import")
            Task { await importIncomingFile(url) }
            return
        }
        guard let route = Route(url: url) else {
            AppLogger.warn("Unrecognized URL: \(url.scheme ?? "nil")", category: "deeplink")
            return
        }
        router.navigate(to: route)
    }

    /// File extension + byte size only — never the filename or full path,
    /// which can carry PII (a scanned document's original name) into Sentry.
    private func fileDescription(for url: URL) -> String {
        let ext = url.pathExtension.isEmpty ? "unknown" : url.pathExtension.lowercased()
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
        let sizeText = bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "unknown size"
        return "\(ext), \(sizeText)"
    }

    /// Mail/Files "Open in PaperTrail": the URL is only guaranteed valid for
    /// this callback, so it's copied into a local inbox before the security
    /// scope is released, then run through the same extraction pipeline as
    /// manual Photos/Files import (`ImportPipeline`, shared with `ImportView`).
    private func importIncomingFile(_ url: URL) async {
        // Checked and set synchronously, before any `await` in this
        // function, so a concurrently-running `ShareInboxDrain` can't slip
        // past this guard and race to assign `pendingImportPayload` too.
        guard !router.isImporting else {
            AppLogger.warn("Import ignored — another import is already in flight", category: "import")
            return
        }
        router.isImporting = true
        defer { router.isImporting = false }

        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        guard let localCopy = DocumentInbox.copy(url) else {
            AppLogger.error("Failed to copy incoming file to inbox: \(fileDescription(for: url))", category: "import")
            return
        }
        defer { DocumentInbox.delete(localCopy) }

        let images = ImportPipeline.images(fromFileURLs: [localCopy])
        guard !images.isEmpty else {
            AppLogger.error("No images extracted from incoming file: \(fileDescription(for: url))", category: "import")
            return
        }

        let learned = MerchantLearningService(modelContext: modelContext).learnedMerchantNames()
        let result = await ScanningService().process(images: images, type: .receipt, learnedMerchants: learned)

        if router.showCapture {
            // Let the capture cover's dismissal animation settle before
            // presenting the import review cover — two full-screen covers
            // fighting over presentation at once breaks SwiftUI's transition.
            router.showCapture = false
            try? await Task.sleep(for: .milliseconds(600))
        }
        router.pendingImportPayload = DraftPayload(type: .receipt, attachments: result.attachments, ocr: result.ocr)
        AppLogger.info("Incoming file routed to review", category: "import")
    }
}

/// Resolves a `pendingRecordID` (from a deep link, notification, quick
/// action, or Spotlight tap) to a live `PurchaseRecord` and pushes
/// `RecordDetailView` — or a not-found state if the record doesn't exist on
/// this device (e.g. it was deleted, or it's a household member's own record
/// that's only mirrored, not stored locally).
private struct RecordDetailByIDView: View {
    @Query private var records: [PurchaseRecord]

    init(recordID: UUID) {
        _records = Query(filter: #Predicate<PurchaseRecord> { $0.id == recordID })
    }

    var body: some View {
        if let record = records.first {
            RecordDetailView(record: record)
        } else {
            ContentUnavailableView("Record not found", systemImage: "questionmark.folder")
                .onAppear {
                    AppLogger.warn("Deep-linked record not found locally", category: "deeplink")
                }
        }
    }
}

// MARK: - Custom tab bar (2 + ＋ + 2)

/// Editorial chrome: a warm-dark bar with four destinations flanking a centered
/// gold capture button. The active destination is gold with a 2px gold underline.
struct PTTabBar: View {
    @Binding var selection: AppTab
    var onCapture: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.library, label: "Library", symbol: "books.vertical")
            tabButton(.warranty, label: "Warranty", symbol: "checkmark.seal")

            captureButton

            tabButton(.search, label: "Search", symbol: "magnifyingglass")
            tabButton(.settings, label: "Settings", symbol: "gearshape")
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .background(
            LinearGradient(colors: [PT.inkPanel, PT.inkCanvas],
                           startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) {
                    Rectangle().fill(PT.hair2).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(_ tab: AppTab, label: String, symbol: String) -> some View {
        let isActive = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: isActive ? .semibold : .regular))
                Text(label)
                    .font(PTFont.mono(8.5, medium: isActive))
                    .tracking(0.8)
                    .textCase(.uppercase)
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? AnyShapeStyle(PT.goldFoil) : AnyShapeStyle(Color.clear))
                    .frame(width: 18, height: 2)
            }
            .foregroundStyle(isActive ? PT.gold : PT.txt3)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var captureButton: some View {
        Button(action: onCapture) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(PT.inkStamp)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(colors: [PT.goldHi, PT.gold],
                                   startPoint: .top, endPoint: .bottom),
                    in: Circle()
                )
                .overlay(Circle().stroke(PT.goldHi2.opacity(0.6), lineWidth: 1))
                .shadow(color: PT.gold.opacity(0.5), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .frame(width: 70)
        .offset(y: -6)
        .accessibilityLabel("Capture receipt")
    }
}

#Preview {
    AppShellView()
        .environmentObject(CloudImageSyncManager.shared)
        .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
