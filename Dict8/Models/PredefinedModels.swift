import Foundation

enum PredefinedModels {
    static func getLanguageDictionary(isMultilingual: Bool, provider: ModelProvider = .local) -> [String: String] {
        guard isMultilingual else { return ["en": "English"] }
        switch provider {
        case .nativeApple:
            return allLanguages.filter { ["ar","de","en","es","fr","it","ja","ko","pt","yue","zh"].contains($0.key) }
        case .soniox:
            var filtered = allLanguages.filter {
                ["af","sq","ar","az","eu","be","bn","bs","bg","ca","zh","hr","cs","da","nl","en","et","fi","fr","gl",
                 "de","el","gu","he","hi","hu","id","it","ja","kn","kk","ko","lv","lt","mk","ms","ml","mr","no","fa",
                 "pl","pt","pa","ro","ru","sr","sk","sl","es","sw","sv","tl","ta","te","th","tr","uk","ur","vi","cy"].contains($0.key)
            }
            filtered["auto"] = "Auto-detect"
            return filtered
        default:
            return allLanguages
        }
    }

    static let appleNativeLanguages: [String: String] = [
        "en-US": "English (US)", "en-GB": "English (UK)", "en-CA": "English (Canada)",
        "en-AU": "English (Australia)", "en-IN": "English (India)", "en-IE": "English (Ireland)",
        "en-NZ": "English (NZ)", "en-ZA": "English (SA)", "en-SA": "English (Saudi Arabia)",
        "en-AE": "English (UAE)", "en-SG": "English (Singapore)", "en-PH": "English (Philippines)",
        "en-ID": "English (Indonesia)",
        "es-ES": "Spanish (Spain)", "es-MX": "Spanish (Mexico)", "es-US": "Spanish (US)",
        "es-CO": "Spanish (Colombia)", "es-CL": "Spanish (Chile)", "es-419": "Spanish (Latin America)",
        "fr-FR": "French (France)", "fr-CA": "French (Canada)", "fr-BE": "French (Belgium)", "fr-CH": "French (Switzerland)",
        "de-DE": "German (Germany)", "de-AT": "German (Austria)", "de-CH": "German (Switzerland)",
        "zh-CN": "Chinese Simplified", "zh-TW": "Chinese Traditional (Taiwan)", "zh-HK": "Chinese Traditional (HK)",
        "ja-JP": "Japanese", "ko-KR": "Korean", "yue-CN": "Cantonese",
        "pt-BR": "Portuguese (Brazil)", "pt-PT": "Portuguese (Portugal)",
        "it-IT": "Italian", "it-CH": "Italian (Switzerland)", "ar-SA": "Arabic (Saudi Arabia)",
    ]

    static var models: [any TranscriptionModel] {
        #if arch(arm64)
        return predefinedModels + CustomModelManager.shared.customModels
        #else
        return predefinedModels.filter { $0.provider != .nativeApple } + CustomModelManager.shared.customModels
        #endif
    }

    // swiftlint:disable function_body_length
    private static let predefinedModels: [any TranscriptionModel] = [
        PredefinedModel(name: "parakeet-redux", displayName: "Parakeet Redux", description: "Moondream's ternary Parakeet Redux: 7x smaller download (~220 MB), faster on CPU, same 25 European languages", provider: .parakeet, size: "220 MB", speed: 0.99, accuracy: 0.93, ramUsage: 0.4),
        PredefinedModel(name: "parakeet-tdt-0.6b-v3", displayName: "Parakeet V3", description: "NVIDIA's Parakeet V3 with multilingual support across English and 25 European languages", provider: .parakeet, size: "494 MB", speed: 0.99, accuracy: 0.94, ramUsage: 0.8),
        PredefinedModel(name: "parakeet-tdt-0.6b-v2", displayName: "Parakeet V2", description: "NVIDIA's Parakeet V2 optimized for lightning-fast English-only transcription", provider: .parakeet, size: "474 MB", speed: 0.99, accuracy: 0.94, ramUsage: 0.8, isMultilingual: false),

        PredefinedModel(name: "apple-speech", displayName: "Apple Speech", description: "Built-in SpeechAnalyzer. Live drafts while you speak, no download. Requires macOS 26", provider: .nativeApple),

        PredefinedModel(name: "ggml-tiny",    displayName: "Tiny",             description: "Tiny model, fastest, least accurate",                       provider: .local, size: "75 MB",  speed: 0.95, accuracy: 0.6,  ramUsage: 0.3),
        PredefinedModel(name: "ggml-tiny.en", displayName: "Tiny (English)",   description: "Tiny model optimized for English",                          provider: .local, size: "75 MB",  speed: 0.95, accuracy: 0.65, ramUsage: 0.3, isMultilingual: false),
        PredefinedModel(name: "ggml-base",    displayName: "Base",             description: "Base model, good balance of speed and accuracy",            provider: .local, size: "142 MB", speed: 0.85, accuracy: 0.72, ramUsage: 0.5),
        PredefinedModel(name: "ggml-base.en", displayName: "Base (English)",   description: "Base model optimized for English",                          provider: .local, size: "142 MB", speed: 0.85, accuracy: 0.75, ramUsage: 0.5, isMultilingual: false),
        PredefinedModel(name: "ggml-large-v2",          displayName: "Large v2",                  description: "Large model v2, slower but more accurate",         provider: .local, size: "2.9 GB", speed: 0.3,  accuracy: 0.96, ramUsage: 3.8),
        PredefinedModel(name: "ggml-large-v3",          displayName: "Large v3",                  description: "Large model v3, very slow but most accurate",      provider: .local, size: "2.9 GB", speed: 0.3,  accuracy: 0.98, ramUsage: 3.9),
        PredefinedModel(name: "ggml-large-v3-turbo",    displayName: "Large v3 Turbo",            description: "Large v3 Turbo, faster than v3 similar accuracy",  provider: .local, size: "1.5 GB", speed: 0.75, accuracy: 0.97, ramUsage: 1.8),
        PredefinedModel(name: "ggml-large-v3-turbo-q5_0", displayName: "Large v3 Turbo (Quantized)", description: "Quantized Large v3 Turbo, fast with good accuracy", provider: .local, size: "547 MB", speed: 0.75, accuracy: 0.95, ramUsage: 1.0),

        PredefinedModel(name: "whisper-large-v3-turbo",  displayName: "Whisper Large v3 Turbo (Groq)",  description: "Groq's lightning-speed Whisper inference",                  provider: .groq,      speed: 0.65, accuracy: 0.95),
        PredefinedModel(name: "scribe_v1",                displayName: "Scribe v1 (ElevenLabs)",         description: "ElevenLabs' Scribe for fast & accurate transcription",      provider: .elevenLabs, speed: 0.7,  accuracy: 0.98),
        PredefinedModel(name: "scribe_v2",                displayName: "Scribe V2 Realtime (ElevenLabs)", description: "ElevenLabs' Scribe V2 Realtime, most accurate",            provider: .elevenLabs, speed: 0.99, accuracy: 0.98),
        PredefinedModel(name: "nova-3",                   displayName: "Nova 3 Realtime (Deepgram)",     description: "Deepgram's latest Nova 3 for realtime transcription",       provider: .deepgram,   speed: 0.99, accuracy: 0.96),
        PredefinedModel(name: "nova-3-medical",           displayName: "Nova 3 Medical (Deepgram)",      description: "Specialized medical transcription for clinical environments", provider: .deepgram,   speed: 0.99, accuracy: 0.96, isMultilingual: false),
        PredefinedModel(name: "voxtral-mini-latest",      displayName: "Voxtral Transcribe 2 (Mistral)", description: "Mistral's latest fast and accurate transcription",           provider: .mistral,    speed: 0.8,  accuracy: 0.98),
        PredefinedModel(name: "voxtral-mini-transcribe-realtime-2602", displayName: "Voxtral Realtime (Mistral)", description: "Mistral's Voxtral Realtime streaming transcription", provider: .mistral, speed: 0.99, accuracy: 0.97),
        PredefinedModel(name: "gemini-2.5-pro",           displayName: "Gemini 2.5 Pro",                description: "Google's advanced high-quality transcription",               provider: .gemini,     speed: 0.7,  accuracy: 0.97),
        PredefinedModel(name: "gemini-2.5-flash",         displayName: "Gemini 2.5 Flash",              description: "Google's optimized low-latency transcription",               provider: .gemini,     speed: 0.9,  accuracy: 0.95),
        PredefinedModel(name: "gemini-3-pro-preview",     displayName: "Gemini 3 Pro",                  description: "Google's latest enhanced transcription",                     provider: .gemini,     speed: 0.75, accuracy: 0.97),
        PredefinedModel(name: "gemini-3-flash-preview",   displayName: "Gemini 3 Flash",                description: "Google's newest fast model with superior speed",             provider: .gemini,     speed: 0.92, accuracy: 0.95),
        PredefinedModel(name: "stt-async-v4",             displayName: "Soniox V4",                     description: "Soniox async transcription v4 with human-parity accuracy",  provider: .soniox,     speed: 0.8,  accuracy: 0.98),
        PredefinedModel(name: "stt-rt-v4",                displayName: "Soniox Realtime V4",            description: "Soniox real-time streaming v4 for low-latency transcription", provider: .soniox,    speed: 0.99, accuracy: 0.97),
    ]
    // swiftlint:enable function_body_length

    static let allLanguages: [String: String] = [
        "auto": "Auto-detect", "af": "Afrikaans", "am": "Amharic", "ar": "Arabic", "as": "Assamese",
        "az": "Azerbaijani", "ba": "Bashkir", "be": "Belarusian", "bg": "Bulgarian", "bn": "Bengali",
        "bo": "Tibetan", "br": "Breton", "bs": "Bosnian", "ca": "Catalan", "cs": "Czech",
        "cy": "Welsh", "da": "Danish", "de": "German", "el": "Greek", "en": "English",
        "es": "Spanish", "et": "Estonian", "eu": "Basque", "fa": "Persian", "fi": "Finnish",
        "fo": "Faroese", "fr": "French", "gl": "Galician", "gu": "Gujarati", "ha": "Hausa",
        "haw": "Hawaiian", "he": "Hebrew", "hi": "Hindi", "hr": "Croatian", "ht": "Haitian Creole",
        "hu": "Hungarian", "hy": "Armenian", "id": "Indonesian", "is": "Icelandic", "it": "Italian",
        "ja": "Japanese", "jw": "Javanese", "ka": "Georgian", "kk": "Kazakh", "km": "Khmer",
        "kn": "Kannada", "ko": "Korean", "la": "Latin", "lb": "Luxembourgish", "ln": "Lingala",
        "lo": "Lao", "lt": "Lithuanian", "lv": "Latvian", "mg": "Malagasy", "mi": "Maori",
        "mk": "Macedonian", "ml": "Malayalam", "mn": "Mongolian", "mr": "Marathi", "ms": "Malay",
        "mt": "Maltese", "my": "Myanmar", "ne": "Nepali", "nl": "Dutch", "nn": "Norwegian Nynorsk",
        "no": "Norwegian", "oc": "Occitan", "pa": "Punjabi", "pl": "Polish", "ps": "Pashto",
        "pt": "Portuguese", "ro": "Romanian", "ru": "Russian", "sa": "Sanskrit", "sd": "Sindhi",
        "si": "Sinhala", "sk": "Slovak", "sl": "Slovenian", "sn": "Shona", "so": "Somali",
        "sq": "Albanian", "sr": "Serbian", "su": "Sundanese", "sv": "Swedish", "sw": "Swahili",
        "ta": "Tamil", "te": "Telugu", "tg": "Tajik", "th": "Thai", "tk": "Turkmen",
        "tl": "Tagalog", "tr": "Turkish", "tt": "Tatar", "uk": "Ukrainian", "ur": "Urdu",
        "uz": "Uzbek", "vi": "Vietnamese", "yi": "Yiddish", "yo": "Yoruba", "yue": "Cantonese",
        "zh": "Chinese",
    ]
}
