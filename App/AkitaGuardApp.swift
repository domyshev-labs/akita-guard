import SwiftUI

@main struct AkitaGuardApp: App {
    @StateObject private var store = AccessStore()

    #if DEBUG
    @MainActor private func configureFromDeveloperLaunch() async {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["AKITA_SETUP_TOKEN"],
              let server = environment["AKITA_SETUP_SERVER"] else { return }
        unsetenv("AKITA_SETUP_TOKEN")
        unsetenv("AKITA_SETUP_SERVER")
        let connected = await store.configure(server: server, token: token)
        // Receipt contains only booleans, never credentials or server data.
        let receipt = ["configured": store.configured, "connected": connected]
        if let data = try? JSONSerialization.data(withJSONObject: receipt),
           let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: directory.appendingPathComponent("developer-setup-result.json"), options: .atomic)
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task {
                    #if DEBUG
                    await configureFromDeveloperLaunch()
                    #endif
                }
                .tint(Color("AccentColor"))
        }
    }
}
