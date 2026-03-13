import SwiftUI

@main
struct PaperTrailApp: App {
    @StateObject private var store = PurchaseRecordStore()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(store)
        }
    }
}
