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
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
    }
}

private enum AppTab {
    case library
    case settings
}

#Preview {
    AppShellView()
}
