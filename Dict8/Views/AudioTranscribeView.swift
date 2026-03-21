import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AVFoundation

struct AudioTranscribeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var whisperState: WhisperState
    @StateObject private var transcriptionManager = AudioTranscriptionManager.shared
    @State private var isDropTargeted = false
    @State private var selectedAudioURL: URL?
    @State private var isAudioFileSelected = false
    @State private var isEnhancementEnabled = false
    @State private var selectedPromptId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if transcriptionManager.isProcessing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(transcriptionManager.processingPhase.message).font(.headline)
                }
                .padding()
            } else {
                dropZoneView
            }

            Divider()

            if let transcription = transcriptionManager.currentTranscription {
                TranscriptionResultView(transcription: transcription)
            }
        }
        .onDrop(of: [.fileURL, .data, .audio, .movie], isTargeted: $isDropTargeted) { providers in
            if !transcriptionManager.isProcessing && !isAudioFileSelected {
                handleDroppedFile(providers); return true
            }
            return false
        }
        .alert("Error", isPresented: .constant(transcriptionManager.errorMessage != nil)) {
            Button("OK", role: .cancel) { transcriptionManager.errorMessage = nil }
        } message: {
            if let errorMessage = transcriptionManager.errorMessage { Text(errorMessage) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileForTranscription)) { notification in
            if let url = notification.userInfo?["url"] as? URL { validateAndSetAudioFile(url) }
        }
    }

    private var dropZoneView: some View {
        VStack(spacing: 12) {
            if isAudioFileSelected {
                Text("Audio file selected: \(selectedAudioURL?.lastPathComponent ?? "")").font(.headline)

                if let enhancementService = whisperState.getEnhancementService() {
                    HStack(spacing: 12) {
                        Toggle("AI Enhancement", isOn: $isEnhancementEnabled)
                            .toggleStyle(.switch)
                            .onChange(of: isEnhancementEnabled) { _, newValue in enhancementService.isEnhancementEnabled = newValue }

                        if isEnhancementEnabled && !enhancementService.allPrompts.isEmpty {
                            Divider().frame(height: 20)
                            Picker("Prompt", selection: Binding(
                                get: { selectedPromptId ?? enhancementService.allPrompts.first?.id ?? UUID() },
                                set: { selectedPromptId = $0; enhancementService.selectedPromptId = $0 }
                            )) {
                                ForEach(enhancementService.allPrompts) { Text($0.title).tag($0.id) }
                            }
                            .fixedSize()
                        }
                    }
                    .onAppear {
                        isEnhancementEnabled = enhancementService.isEnhancementEnabled
                        selectedPromptId = enhancementService.selectedPromptId
                    }
                }

                HStack(spacing: 12) {
                    Button("Start Transcription") {
                        if let url = selectedAudioURL {
                            transcriptionManager.startProcessing(url: url, modelContext: modelContext, whisperState: whisperState)
                        }
                    }.glassActionButton()

                    Button("Choose Different File") { selectedAudioURL = nil; isAudioFileSelected = false }.buttonStyle(.bordered)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .foregroundColor(isDropTargeted ? .accentColor : .secondary.opacity(0.5))

                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc").font(.headline).foregroundColor(isDropTargeted ? .accentColor : .secondary)
                        Text("Drop audio or video file here").font(.headline)
                        Text("or").foregroundStyle(.secondary)
                        Button("Choose File") { selectFile() }.buttonStyle(.bordered)
                    }
                    .padding()
                }
                .frame(height: 200)
            }

            Text("Supported formats: WAV, MP3, M4A, AIFF, MP4, MOV, AAC, FLAC, CAF, AMR, OGG, OPUS, 3GP")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .movie]
        if panel.runModal() == .OK, let url = panel.url { selectedAudioURL = url; isAudioFileSelected = true }
    }

    private func handleDroppedFile(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        let typeIdentifiers = [UTType.fileURL.identifier, UTType.audio.identifier, UTType.movie.identifier, UTType.data.identifier, "public.file-url"]
        for typeIdentifier in typeIdentifiers {
            if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { (item, error) in
                    if let error = error { print("Error loading dropped file with type \(typeIdentifier): \(error)"); return }
                    var fileURL: URL?
                    if let url = item as? URL { fileURL = url }
                    else if let data = item as? Data {
                        if let url = URL(dataRepresentation: data, relativeTo: nil) { fileURL = url }
                        else if let urlString = String(data: data, encoding: .utf8), let url = URL(string: urlString) { fileURL = url }
                    } else if let urlString = item as? String { fileURL = URL(string: urlString) }
                    if let finalURL = fileURL { DispatchQueue.main.async { self.validateAndSetAudioFile(finalURL) }; return }
                }
                break
            }
        }
    }

    private func validateAndSetAudioFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard SupportedMedia.isSupported(url: url) else { return }
        selectedAudioURL = url; isAudioFileSelected = true
    }
}
