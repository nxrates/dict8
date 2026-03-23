import SwiftUI
import AppKit

struct ModelCardView: View {
    let model: any TranscriptionModel
    @ObservedObject var whisperState: WhisperState
    var deleteAction: (() -> Void)?
    var setDefaultAction: () -> Void
    var downloadAction: (() -> Void)?
    var editAction: ((CustomCloudModel) -> Void)?

    @StateObject private var aiService = AIService()
    @State private var isConfigExpanded = false
    @State private var apiKey = ""
    @State private var isVerifying = false
    @State private var verified: Bool? = nil
    @State private var verificationError: String?
    @State private var isConfiguredState = false

    private var isCurrent: Bool { whisperState.currentTranscriptionModel?.name == model.name }
    private var isCloud: Bool { model.provider.isCloud }

    private var isUnsupportedOS: Bool {
        if model.provider == .nativeApple {
            if #available(macOS 26, *) { return false } else { return true }
        }
        return false
    }

    private var isDownloaded: Bool {
        switch model.provider {
        case .local: return whisperState.availableModels.contains { $0.name == model.name }
        case .parakeet: return whisperState.isParakeetModelDownloaded(named: model.name)
        case .nativeApple: if #available(macOS 26, *) { return true } else { return false }
        case .custom: return true
        default: return isConfiguredState
        }
    }

    private var isDownloading: Bool {
        switch model.provider {
        case .local: return whisperState.downloadProgress.keys.contains(model.name + "_main") || whisperState.downloadProgress.keys.contains(model.name + "_coreml")
        case .parakeet: return whisperState.parakeetDownloadStates[model.name] ?? false
        default: return false
        }
    }

    private var isWarming: Bool {
        #if canImport(whisper)
        model.provider == .local && WhisperModelWarmupCoordinator.shared.isWarming(modelNamed: model.name)
        #else
        false
        #endif
    }

    private var modelURL: URL? { whisperState.availableModels.first { $0.name == model.name }?.url }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.displayName).font(.body)
                        providerTag
                        statusText
                    }
                    HStack(spacing: 6) {
                        Text(model.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if !model.size.isEmpty && (model.provider == .local || model.provider == .parakeet) {
                            Text("·").font(.caption).foregroundStyle(.secondary)
                            Text(model.size).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                actionButtons
            }

            downloadProgressSection

            if isCloud && isConfigExpanded {
                apiKeySection.padding(.top, 4)
            }
        }
        .opacity(isUnsupportedOS ? 0.5 : 1.0)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.15) : Color.clear)
        .onAppear {
            guard isCloud else { return }
            if let saved = APIKeyManager.shared.getAPIKey(forProvider: model.provider.rawValue) { apiKey = saved; verified = true }
            isConfiguredState = APIKeyManager.shared.hasAPIKey(forProvider: model.provider.rawValue)
        }
    }

    // MARK: - Status Text

    @ViewBuilder private var providerTag: some View {
        switch model.provider {
        case .local, .parakeet:
            Text("Local").font(.caption).foregroundStyle(.green)
        case .nativeApple:
            Text("Built-in").font(.caption).foregroundStyle(.green)
        case .custom:
            Text("Custom").font(.caption).foregroundStyle(.secondary)
        default:
            if isCloud {
                Text("Cloud").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var statusText: some View {
        if isUnsupportedOS {
            Text("Requires macOS 26").font(.caption).foregroundStyle(.secondary)
        } else if isCurrent && needsDownload {
            Text("Default — Not Downloaded").font(.caption).foregroundStyle(.orange)
        } else if isCurrent {
            Text("Default").font(.caption).fontWeight(.semibold).foregroundColor(.accentColor)
        } else if isCloud {
            Text(isConfiguredState ? "Configured" : "Setup Required")
                .font(.caption).foregroundStyle(isConfiguredState ? .green : .orange)
        } else if isDownloaded {
            Text("Downloaded").font(.caption).foregroundStyle(.green)
        }
    }

    // MARK: - Download Progress

    @ViewBuilder private var downloadProgressSection: some View {
        if model.provider == .local && isDownloading {
            DownloadProgressView(modelName: model.name, downloadProgress: whisperState.downloadProgress)
        } else if model.provider == .parakeet && isDownloading {
            ProgressView(value: whisperState.downloadProgress[model.name] ?? 0)
        }
    }

    // MARK: - Action Buttons

    private var needsDownload: Bool {
        !isCloud && !isDownloaded && (model.provider == .local || model.provider == .parakeet)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if isUnsupportedOS {
                Text("Not Available").font(.caption).foregroundStyle(.secondary)
            } else if isCurrent && !needsDownload {
                Text("Default Model").font(.caption).foregroundStyle(.secondary)
            } else if isCurrent && needsDownload {
                Button(isDownloading ? "Downloading..." : "Download") { downloadAction?() }
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(isDownloading)
            } else if isWarming {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Optimizing...").font(.caption).foregroundStyle(.secondary) }
            } else if isDownloaded || (isCloud && isConfiguredState) {
                Button("Set as Default") { setDefaultAction() }.buttonStyle(.bordered).controlSize(.small)
            } else if isCloud && !isConfiguredState {
                Button("Configure") { withAnimation { isConfigExpanded.toggle() } }
                    .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button(isDownloading ? "Downloading..." : "Download") { downloadAction?() }
                    .buttonStyle(.bordered).controlSize(.small).disabled(isDownloading)
            }
            overflowMenu
        }
    }

    // MARK: - Overflow Menu

    @ViewBuilder private var overflowMenu: some View {
        let showMenu = isDownloaded || (isCloud && isConfiguredState) || model.provider == .custom
        if showMenu && !isCurrent {
            Menu {
                if let customModel = model as? CustomCloudModel, let editAction {
                    Button { editAction(customModel) } label: { Label("Edit Model", systemImage: "pencil") }
                }
                if isCloud && isConfiguredState {
                    Button { clearAPIKey() } label: { Label("Remove API Key", systemImage: "trash") }
                }
                if model.provider == .local || model.provider == .parakeet {
                    Button {
                        if model.provider == .parakeet { whisperState.showParakeetModelInFinder(model) }
                        else if let url = modelURL { NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "") }
                    } label: { Label("Show in Finder", systemImage: "folder") }
                }
                if let deleteAction { Divider(); Button(role: .destructive) { deleteAction() } label: { Label("Delete", systemImage: "trash") } }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20, height: 20)
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SecureField("Enter your \(model.provider.rawValue) API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder).disabled(isVerifying)
                Button { verifyAPIKey() } label: {
                    if isVerifying { ProgressView().controlSize(.small) } else { Text("Verify") }
                }
                .buttonStyle(.bordered).controlSize(.small).disabled(apiKey.isEmpty || isVerifying)
            }
            if let verified {
                Text(verified ? "API key verified!" : (verificationError ?? "Verification failed"))
                    .font(.caption).foregroundStyle(verified ? .green : .red)
            }
        }
    }

    // MARK: - Actions

    private func verifyAPIKey() {
        guard !apiKey.isEmpty else { return }
        isVerifying = true; verified = nil
        aiService.selectedProvider = aiProviderForModel
        aiService.saveAPIKey(apiKey) { isValid, errorMessage in
            DispatchQueue.main.async {
                isVerifying = false
                if isValid {
                    verified = true; verificationError = nil
                    APIKeyManager.shared.saveAPIKey(apiKey, forProvider: model.provider.rawValue)
                    isConfiguredState = true; withAnimation { isConfigExpanded = false }
                } else { verified = false; verificationError = errorMessage }
            }
        }
    }

    private var aiProviderForModel: AIProvider {
        switch model.provider {
        case .groq: return .groq; case .elevenLabs: return .elevenLabs; case .deepgram: return .deepgram
        case .mistral: return .mistral; case .gemini: return .gemini; case .soniox: return .soniox
        default: return .groq
        }
    }

    private func clearAPIKey() {
        APIKeyManager.shared.deleteAPIKey(forProvider: model.provider.rawValue)
        apiKey = ""; verified = nil; verificationError = nil; isConfiguredState = false
        if isCurrent { whisperState.currentTranscriptionModel = nil; UserDefaults.standard.removeObject(forKey: "CurrentTranscriptionModel") }
        withAnimation { isConfigExpanded = false }
    }
}
