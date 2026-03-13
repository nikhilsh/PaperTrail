import SwiftUI

@main
struct PaperTrailApp: App {
    @State private var store = PurchaseRecordStore()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(store)
        }
    }
}
