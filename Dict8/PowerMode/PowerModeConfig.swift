import Foundation
import KeyboardShortcuts

struct PowerModeConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var emoji: String
    var appConfigs: [AppConfig]?
    var urlConfigs: [URLConfig]?
    var isAIEnhancementEnabled: Bool
    var selectedPrompt: String?
    var selectedTranscriptionModelName: String?
    var selectedLanguage: String?
    var useScreenCapture: Bool
    var selectedAIProvider: String?
    var selectedAIModel: String?
    var isAutoSendEnabled: Bool = false
    var isEnabled: Bool = true
    var isDefault: Bool = false
    var hotkeyShortcut: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, appConfigs, urlConfigs, isAIEnhancementEnabled, selectedPrompt, selectedLanguage,
             useScreenCapture, selectedAIProvider, selectedAIModel, isAutoSendEnabled, isEnabled, isDefault,
             hotkeyShortcut, selectedWhisperModel, selectedTranscriptionModelName
    }

    init(id: UUID = UUID(), name: String, emoji: String, appConfigs: [AppConfig]? = nil,
         urlConfigs: [URLConfig]? = nil, isAIEnhancementEnabled: Bool, selectedPrompt: String? = nil,
         selectedTranscriptionModelName: String? = nil, selectedLanguage: String? = nil, useScreenCapture: Bool = false,
         selectedAIProvider: String? = nil, selectedAIModel: String? = nil, isAutoSendEnabled: Bool = false,
         isEnabled: Bool = true, isDefault: Bool = false, hotkeyShortcut: String? = nil) {
        self.id = id; self.name = name; self.emoji = emoji
        self.appConfigs = appConfigs; self.urlConfigs = urlConfigs
        self.isAIEnhancementEnabled = isAIEnhancementEnabled; self.selectedPrompt = selectedPrompt
        self.useScreenCapture = useScreenCapture; self.isAutoSendEnabled = isAutoSendEnabled
        self.selectedAIProvider = selectedAIProvider ?? UserDefaults.standard.string(forKey: "selectedAIProvider")
        self.selectedAIModel = selectedAIModel
        self.selectedTranscriptionModelName = selectedTranscriptionModelName ?? UserDefaults.standard.string(forKey: "CurrentTranscriptionModel")
        self.selectedLanguage = selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
        self.isEnabled = isEnabled; self.isDefault = isDefault; self.hotkeyShortcut = hotkeyShortcut
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        emoji = try c.decode(String.self, forKey: .emoji)
        appConfigs = try c.decodeIfPresent([AppConfig].self, forKey: .appConfigs)
        urlConfigs = try c.decodeIfPresent([URLConfig].self, forKey: .urlConfigs)
        isAIEnhancementEnabled = try c.decode(Bool.self, forKey: .isAIEnhancementEnabled)
        selectedPrompt = try c.decodeIfPresent(String.self, forKey: .selectedPrompt)
        selectedLanguage = try c.decodeIfPresent(String.self, forKey: .selectedLanguage)
        useScreenCapture = try c.decode(Bool.self, forKey: .useScreenCapture)
        selectedAIProvider = try c.decodeIfPresent(String.self, forKey: .selectedAIProvider)
        selectedAIModel = try c.decodeIfPresent(String.self, forKey: .selectedAIModel)
        isAutoSendEnabled = try c.decodeIfPresent(Bool.self, forKey: .isAutoSendEnabled) ?? false
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        hotkeyShortcut = try c.decodeIfPresent(String.self, forKey: .hotkeyShortcut)
        selectedTranscriptionModelName = try c.decodeIfPresent(String.self, forKey: .selectedTranscriptionModelName)
            ?? (try c.decodeIfPresent(String.self, forKey: .selectedWhisperModel))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(emoji, forKey: .emoji)
        try c.encodeIfPresent(appConfigs, forKey: .appConfigs); try c.encodeIfPresent(urlConfigs, forKey: .urlConfigs)
        try c.encode(isAIEnhancementEnabled, forKey: .isAIEnhancementEnabled)
        try c.encodeIfPresent(selectedPrompt, forKey: .selectedPrompt)
        try c.encodeIfPresent(selectedLanguage, forKey: .selectedLanguage)
        try c.encode(useScreenCapture, forKey: .useScreenCapture)
        try c.encodeIfPresent(selectedAIProvider, forKey: .selectedAIProvider)
        try c.encodeIfPresent(selectedAIModel, forKey: .selectedAIModel)
        try c.encode(isAutoSendEnabled, forKey: .isAutoSendEnabled)
        try c.encodeIfPresent(selectedTranscriptionModelName, forKey: .selectedTranscriptionModelName)
        try c.encode(isEnabled, forKey: .isEnabled); try c.encode(isDefault, forKey: .isDefault)
        try c.encodeIfPresent(hotkeyShortcut, forKey: .hotkeyShortcut)
    }

    static func == (lhs: PowerModeConfig, rhs: PowerModeConfig) -> Bool { lhs.id == rhs.id }
}

struct AppConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var bundleIdentifier: String
    var appName: String
    init(id: UUID = UUID(), bundleIdentifier: String, appName: String) {
        self.id = id; self.bundleIdentifier = bundleIdentifier; self.appName = appName
    }
    static func == (lhs: AppConfig, rhs: AppConfig) -> Bool { lhs.id == rhs.id }
}

struct URLConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var url: String
    init(id: UUID = UUID(), url: String) { self.id = id; self.url = url }
    static func == (lhs: URLConfig, rhs: URLConfig) -> Bool { lhs.id == rhs.id }
}

class PowerModeManager: ObservableObject {
    static let shared = PowerModeManager()
    @Published var configurations: [PowerModeConfig] = []
    @Published var activeConfiguration: PowerModeConfig?
    private let configKey = "powerModeConfigurationsV2"
    private let activeConfigIdKey = "activeConfigurationId"

    private init() {
        loadConfigurations()
        if let id = UserDefaults.standard.string(forKey: activeConfigIdKey).flatMap(UUID.init) {
            activeConfiguration = configurations.first { $0.id == id }
        }
    }

    private func loadConfigurations() {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let configs = try? JSONDecoder().decode([PowerModeConfig].self, from: data) else { return }
        configurations = configs
    }

    func saveConfigurations() {
        if let data = try? JSONEncoder().encode(configurations) { UserDefaults.standard.set(data, forKey: configKey) }
        NotificationCenter.default.post(name: NSNotification.Name("PowerModeConfigurationsDidChange"), object: nil)
    }

    func addConfiguration(_ config: PowerModeConfig) {
        guard !configurations.contains(where: { $0.id == config.id }) else { return }
        configurations.append(config); saveConfigurations()
    }

    func removeConfiguration(with id: UUID) {
        KeyboardShortcuts.setShortcut(nil, for: .powerMode(id: id))
        configurations.removeAll { $0.id == id }; saveConfigurations()
    }

    func getConfiguration(with id: UUID) -> PowerModeConfig? { configurations.first { $0.id == id } }

    func updateConfiguration(_ config: PowerModeConfig) {
        guard let i = configurations.firstIndex(where: { $0.id == config.id }) else { return }
        configurations[i] = config; saveConfigurations()
    }

    func moveConfigurations(fromOffsets: IndexSet, toOffset: Int) {
        configurations.move(fromOffsets: fromOffsets, toOffset: toOffset); saveConfigurations()
    }

    func getConfigurationForURL(_ url: String) -> PowerModeConfig? {
        let cleaned = cleanURL(url)
        return enabledConfigurations.first { config in
            config.urlConfigs?.contains { cleaned.contains(cleanURL($0.url)) } == true
        }
    }

    func getConfigurationForApp(_ bundleId: String) -> PowerModeConfig? {
        enabledConfigurations.first { $0.appConfigs?.contains { $0.bundleIdentifier == bundleId } == true }
    }

    func getDefaultConfiguration() -> PowerModeConfig? { configurations.first { $0.isEnabled && $0.isDefault } }
    func hasDefaultConfiguration() -> Bool { configurations.contains { $0.isDefault } }

    func setAsDefault(configId: UUID, skipSave: Bool = false) {
        for i in configurations.indices { configurations[i].isDefault = (configurations[i].id == configId) }
        if !skipSave { saveConfigurations() }
    }

    var enabledConfigurations: [PowerModeConfig] { configurations.filter { $0.isEnabled } }

    func cleanURL(_ url: String) -> String {
        url.lowercased()
            .replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setActiveConfiguration(_ config: PowerModeConfig?) {
        activeConfiguration = config
        UserDefaults.standard.set(config?.id.uuidString, forKey: activeConfigIdKey)
        objectWillChange.send()
    }

    var currentActiveConfiguration: PowerModeConfig? { activeConfiguration }

    func isEmojiInUse(_ emoji: String) -> Bool { configurations.contains { $0.emoji == emoji } }
}
