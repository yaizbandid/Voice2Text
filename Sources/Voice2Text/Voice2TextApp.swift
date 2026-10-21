import SwiftUI

@main
struct Voice2TextApp: App {
    @StateObject private var state = AppState()
    @StateObject private var analysis = AnalysisState()

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("ถอดเสียง", systemImage: "waveform") }
                AnalysisRootView()
                    .tabItem { Label("วิเคราะห์คลิป", systemImage: "chart.bar.doc.horizontal") }
            }
                .environmentObject(state)
                .environmentObject(analysis)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    analysis.appState = state
                    state.loadModelIfNeeded()
                }
        }
        .defaultSize(width: 960, height: 680)

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(analysis)
        }
    }
}
