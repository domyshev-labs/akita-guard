import SwiftUI

@main struct AkitaGuardApp: App {
    @StateObject private var store = AccessStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Color("AccentColor"))
        }
    }
}
