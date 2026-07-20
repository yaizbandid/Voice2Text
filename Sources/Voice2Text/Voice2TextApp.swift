import SwiftUI

@main
struct Voice2TextApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    state.loadModelIfNeeded()
                }
        }
        .defaultSize(width: 780, height: 640)

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}
