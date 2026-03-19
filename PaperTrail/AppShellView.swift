import SwiftUI

struct AppShellView: View {
    @State private var selectedTab: AppTab = .library

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "tray.full")
            }
            .tag(AppTab.library)

            NavigationStack {
                CaptureView()
            }
            .tabItem {
                Label("Capture", systemImage: "plus.viewfinder")
            }
            .tag(AppTab.capture)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .tint(.blue)
    }
}

private enum AppTab {
    case library
    case capture
    case settings
}

#Preview {
    AppShellView()
        .modelContainer(for: [PurchaseRecord.self, Attachment.self], inMemory: true)
}
