import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @State private var selectedTab = 0
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            ModelManagementView(whisperState: whisperState)
                .tabItem { Label("Dictate", systemImage: "waveform") }
                .tag(0)

            EnhancementSettingsView()
                .tabItem { Label("Transform", systemImage: "wand.and.stars") }
                .tag(1)

            TranscriptionHistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(2)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings.toggle() } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(whisperState)
                .frame(minWidth: 600, minHeight: 500)
        }
        .frame(minWidth: 700, minHeight: 600)
        .applyGlassToolbar()
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = notification.userInfo?["destination"] as? String {
                switch destination {
                case "Settings": showSettings = true
                case "AI Models", "Speech to Text": selectedTab = 0
                case "Enhancement": selectedTab = 1
                case "History": selectedTab = 2
                default: break
                }
            }
        }
    }
}

// MARK: - Glass Toolbar Modifier

private struct GlassToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            content
        }
    }
}

private extension View {
    func applyGlassToolbar() -> some View {
        modifier(GlassToolbarModifier())
    }
}
