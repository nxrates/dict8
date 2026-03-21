import Foundation

enum ModelProvider: String, Codable, Hashable, CaseIterable {
    case local = "Local"
    case parakeet = "Parakeet"
    case groq = "Groq"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case mistral = "Mistral"
    case gemini = "Gemini"
    case soniox = "Soniox"
    case custom = "Custom"
    case nativeApple = "Native Apple"

    var isCloud: Bool {
        [.groq, .elevenLabs, .deepgram, .mistral, .gemini, .soniox].contains(self)
    }
}

protocol TranscriptionModel: Identifiable, Hashable {
    var id: UUID { get }
    var name: String { get }
    var displayName: String { get }
    var description: String { get }
    var provider: ModelProvider { get }
    var isMultilingualModel: Bool { get }
    var supportedLanguages: [String: String] { get }
    var speed: Double { get }
    var accuracy: Double { get }
    var size: String { get }
    var ramUsage: Double { get }
}

extension TranscriptionModel {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var language: String { isMultilingualModel ? "Multilingual" : "English-only" }
    var speed: Double { 0 }
    var accuracy: Double { 0 }
    var size: String { "" }
    var ramUsage: Double { 0 }
    var downloadURL: String { "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(name).bin" }
    var filename: String { "\(name).bin" }
}

// Unified struct for all predefined models (local, parakeet, cloud, native)
struct PredefinedModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider
    let size: String
    let speed: Double
    let accuracy: Double
    let ramUsage: Double
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    init(name: String, displayName: String, description: String, provider: ModelProvider,
         size: String = "", speed: Double = 0, accuracy: Double = 0, ramUsage: Double = 0,
         isMultilingual: Bool = true, supportedLanguages: [String: String]? = nil) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.provider = provider
        self.size = size
        self.speed = speed
        self.accuracy = accuracy
        self.ramUsage = ramUsage
        self.isMultilingualModel = isMultilingual
        self.supportedLanguages = supportedLanguages ?? PredefinedModels.getLanguageDictionary(isMultilingual: isMultilingual, provider: provider)
    }
}

/// Custom cloud model with API key stored in Keychain.
struct CustomCloudModel: TranscriptionModel, Codable {
    let id: UUID
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .custom
    let apiEndpoint: String
    let modelName: String
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    var apiKey: String {
        APIKeyManager.shared.getCustomModelAPIKey(forModelId: id) ?? ""
    }

    init(id: UUID = UUID(), name: String, displayName: String, description: String, apiEndpoint: String, modelName: String, isMultilingual: Bool = true, supportedLanguages: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.apiEndpoint = apiEndpoint
        self.modelName = modelName
        self.isMultilingualModel = isMultilingual
        self.supportedLanguages = supportedLanguages ?? PredefinedModels.getLanguageDictionary(isMultilingual: isMultilingual)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, displayName, description, apiEndpoint, modelName, isMultilingualModel, supportedLanguages, apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        apiEndpoint = try container.decode(String.self, forKey: .apiEndpoint)
        modelName = try container.decode(String.self, forKey: .modelName)
        isMultilingualModel = try container.decode(Bool.self, forKey: .isMultilingualModel)
        supportedLanguages = try container.decode([String: String].self, forKey: .supportedLanguages)
        if let legacyApiKey = try container.decodeIfPresent(String.self, forKey: .apiKey), !legacyApiKey.isEmpty {
            APIKeyManager.shared.saveCustomModelAPIKey(legacyApiKey, forModelId: id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encode(apiEndpoint, forKey: .apiEndpoint)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(isMultilingualModel, forKey: .isMultilingualModel)
        try container.encode(supportedLanguages, forKey: .supportedLanguages)
    }
}

struct ImportedLocalModel: TranscriptionModel {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let provider: ModelProvider = .local
    let isMultilingualModel: Bool
    let supportedLanguages: [String: String]

    init(fileBaseName: String) {
        self.name = fileBaseName
        self.displayName = fileBaseName
        self.description = "Imported local model"
        self.isMultilingualModel = true
        self.supportedLanguages = PredefinedModels.getLanguageDictionary(isMultilingual: true, provider: .local)
    }
}

// Backward compatibility typealiases
typealias LocalModel = PredefinedModel
typealias ParakeetModel = PredefinedModel
typealias NativeAppleModel = PredefinedModel
typealias CloudModel = PredefinedModel
