import SwiftUI

enum ConfigurationMode: Hashable {
    case add, edit(PowerModeConfig)

    var isAdding: Bool { if case .add = self { return true }; return false }
    var title: String { switch self { case .add: return "Add Power Mode"; case .edit: return "Edit Power Mode" } }

    func hash(into hasher: inout Hasher) {
        switch self { case .add: hasher.combine(0); case .edit(let c): hasher.combine(1); hasher.combine(c.id) }
    }
    static func == (lhs: ConfigurationMode, rhs: ConfigurationMode) -> Bool {
        switch (lhs, rhs) {
        case (.add, .add): return true
        case (.edit(let l), .edit(let r)): return l.id == r.id
        default: return false
        }
    }
}

struct PowerModeView: View {
    @StateObject private var powerModeManager = PowerModeManager.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @State private var configurationMode: ConfigurationMode?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if powerModeManager.configurations.isEmpty {
                    ContentUnavailableView("No Power Modes", systemImage: "bolt.circle",
                        description: Text("Create a power mode to automate your workflow based on apps or websites."))
                } else {
                    List {
                        ForEach($powerModeManager.configurations) { $config in
                            HStack(spacing: 12) {
                                Text(config.emoji).font(.title2)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(config.name).font(.headline)
                                        if config.isDefault {
                                            Text("Default").font(.caption2).fontWeight(.medium)
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Capsule().fill(Color.accentColor)).foregroundColor(.white)
                                        }
                                    }
                                    HStack(spacing: 8) {
                                        if let apps = config.appConfigs, !apps.isEmpty {
                                            Label("\(apps.count) app\(apps.count == 1 ? "" : "s")", systemImage: "app.fill").font(.caption).foregroundColor(.secondary)
                                        }
                                        if let urls = config.urlConfigs, !urls.isEmpty {
                                            Label("\(urls.count) site\(urls.count == 1 ? "" : "s")", systemImage: "globe").font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                Toggle("", isOn: $config.isEnabled).labelsHidden()
                                    .onChange(of: config.isEnabled) { _, _ in powerModeManager.updateConfiguration(config) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                configurationMode = .edit(config)
                                navigationPath.append(configurationMode!)
                            }
                            .opacity(config.isEnabled ? 1.0 : 0.5)
                        }
                        .onDelete { offsets in
                            for i in offsets { powerModeManager.removeConfiguration(with: powerModeManager.configurations[i].id) }
                        }
                        .onMove(perform: powerModeManager.moveConfigurations)
                    }
                }
            }
            .navigationTitle("Power Modes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        configurationMode = .add
                        navigationPath.append(configurationMode!)
                    } label: {
                        Label("Add Power Mode", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: ConfigurationMode.self) { mode in
                ConfigurationView(mode: mode, powerModeManager: powerModeManager)
            }
        }
    }
}
