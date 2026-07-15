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

    /// A record to push onto the Library tab's stack, consumed by
    /// `navigationDestination(item:)` in `AppShellView`.
    var pendingRecordID: UUID?

    /// A document handed to PaperTrail via Mail/Files "Open in PaperTrail",
    /// already run through extraction — consumed by a full-screen cover that
    /// presents the same review screen a manual scan would.
    var pendingImportPayload: DraftPayload?

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
                onCapture: { router.showCapture = true }
            )
        }
        .background(PT.inkCanvas.ignoresSafeArea())
        .environment(router)
        .preferredColorScheme(.dark)
        .tint(PT.gold)
        .fullScreenCover(isPresented: $router.showCapture) {
            NavigationStack {
                CaptureView()
            }
            .tint(PT.gold)
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $router.pendingImportPayload) { payload in
            NavigationStack {
                DraftRecordView(seedType: payload.type, seededAttachments: payload.attachments, seededOCR: payload.ocr)
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
                DigestScheduler.reschedule(modelContext: modelContext)
            }
        }
        .onChange(of: router.selectedTab) { _, newTab in
            // A deep-linked/notification/Spotlight-tapped record push shouldn't
            // ghost-reappear if the user leaves the Library tab and comes back.
            if newTab != .library {
                router.pendingRecordID = nil
            }
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
