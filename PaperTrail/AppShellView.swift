import SwiftUI
import SwiftData

// MARK: - Tabs

enum AppTab: Hashable {
    case library
    case warranty
    case search
    case settings
}

/// Shared navigation state so any screen can deep-link to another tab
/// (e.g. the Library attention banner jumps to the Warranty tab).
@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .library
    var showCapture = false
}

// MARK: - Shell

struct AppShellView: View {
    @State private var router = AppRouter()
    @AppStorage("community.consentPrompted") private var communityConsentPrompted = false
    @AppStorage(CommunityLearning.optOutKey) private var communityLearningEnabled = false
    @State private var showLearningConsent = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Active tab content. Each destination keeps its own NavigationStack.
            Group {
                switch router.selectedTab {
                case .library:
                    NavigationStack { LibraryView() }
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
        .onAppear {
            if !communityConsentPrompted {
                showLearningConsent = true
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
