import Foundation

typealias PromptIcon = String

extension PromptIcon {
    static let allCases: [PromptIcon] = [
        // Document & Text
        "doc.text.fill",
        "textbox",
        "checkmark.seal.fill",
        
        // Communication
        "bubble.left.and.bubble.right.fill",
        "message.fill",
        "envelope.fill",
        
        // Professional
        "person.2.fill",
        "person.wave.2.fill",
        "briefcase.fill",
        
        // Technical
        "curlybraces",
        "terminal.fill",
        "gearshape.fill",
        
        // Content
        "doc.text.image.fill",
        "note",
        "book.fill",
        "bookmark.fill",
        "pencil.circle.fill",
        
        // Media & Creative
        "video.fill",
        "mic.fill",
        "music.note",
        "photo.fill",
        "paintbrush.fill",
        
        // Productivity & Time
        "clock.fill",
        "calendar",
        "list.bullet",
        "checkmark.circle.fill",
        "timer",
        "hourglass",
        "star.fill",
        "flag.fill",
        "tag.fill",
        "folder.fill",
        "paperclip",
        "tray.fill",
        "chart.bar.fill",
        "flame.fill",
        "target",
        "list.clipboard.fill",
        "brain.head.profile",
        "lightbulb.fill",
        "megaphone.fill",
        "heart.fill",
        "map.fill",
        "house.fill",
        "camera.fill",
        "figure.walk",
        "dumbbell.fill",
        "cart.fill",
        "creditcard.fill",
        "graduationcap.fill",
        "airplane",
        "leaf.fill",
        "hand.raised.fill",
        "hand.thumbsup.fill"
    ]
}

struct CustomPrompt: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let promptText: String
    var isActive: Bool
    let icon: PromptIcon
    let description: String?
    let isPredefined: Bool
    let triggerWords: [String]
    let useSystemInstructions: Bool
    
    init(
        id: UUID = UUID(),
        title: String,
        promptText: String,
        isActive: Bool = false,
        icon: PromptIcon = "doc.text.fill",
        description: String? = nil,
        isPredefined: Bool = false,
        triggerWords: [String] = [],
        useSystemInstructions: Bool = true
    ) {
        self.id = id
        self.title = title
        self.promptText = promptText
        self.isActive = isActive
        self.icon = icon
        self.description = description
        self.isPredefined = isPredefined
        self.triggerWords = triggerWords
        self.useSystemInstructions = useSystemInstructions
    }

    enum CodingKeys: String, CodingKey {
        case id, title, promptText, isActive, icon, description, isPredefined, triggerWords, useSystemInstructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        promptText = try container.decode(String.self, forKey: .promptText)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        icon = try container.decode(PromptIcon.self, forKey: .icon)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        isPredefined = try container.decode(Bool.self, forKey: .isPredefined)
        triggerWords = try container.decode([String].self, forKey: .triggerWords)
        useSystemInstructions = try container.decodeIfPresent(Bool.self, forKey: .useSystemInstructions) ?? true
    }
    
    var finalPromptText: String {
        if useSystemInstructions {
            return String(format: AIPrompts.customPromptTemplate, self.promptText)
        } else {
            return self.promptText
        }
    }
}

