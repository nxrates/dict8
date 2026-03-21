import SwiftUI
import AVFoundation

extension TimeInterval {
    func formatTiming() -> String {
        if self < 1 { return String(format: "%.0fms", self * 1000) }
        if self < 60 { return String(format: "%.1fs", self) }
        let minutes = Int(self) / 60; let seconds = self.truncatingRemainder(dividingBy: 60)
        return String(format: "%dm %.0fs", minutes, seconds)
    }

    /// Formats as "M:SS" for audio player / duration display.
    func formatMinutesSeconds() -> String {
        String(format: "%d:%02d", Int(self) / 60, Int(self) % 60)
    }
}

class WaveformGenerator {
    private static let cache = NSCache<NSString, NSArray>()

    static func generateWaveformSamples(from url: URL, sampleCount: Int = 200) async -> [Float] {
        let cacheKey = url.absoluteString as NSString
        if let cachedSamples = cache.object(forKey: cacheKey) as? [Float] { return cachedSamples }
        guard let audioFile = try? AVAudioFile(forReading: url) else { return [] }
        let format = audioFile.processingFormat
        let frameCount = UInt32(audioFile.length)
        let stride = max(1, Int(frameCount) / sampleCount)
        let bufferSize = min(UInt32(4096), frameCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else { return [] }
        do {
            var maxValues = [Float](repeating: 0.0, count: sampleCount)
            var sampleIndex = 0; var framePosition: AVAudioFramePosition = 0
            while sampleIndex < sampleCount && framePosition < AVAudioFramePosition(frameCount) {
                audioFile.framePosition = framePosition; try audioFile.read(into: buffer)
                if let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 { maxValues[sampleIndex] = abs(channelData[0]); sampleIndex += 1 }
                framePosition += AVAudioFramePosition(stride)
            }
            let normalized: [Float] = if let max = maxValues.max(), max > 0 { maxValues.map { $0 / max } } else { maxValues }
            cache.setObject(normalized as NSArray, forKey: cacheKey)
            return normalized
        } catch { return [] }
    }
}

class AudioPlayerManager: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var waveformSamples: [Float] = []
    @Published var isLoadingWaveform = false

    func loadAudio(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay(); duration = audioPlayer?.duration ?? 0; isLoadingWaveform = true
            Task {
                let samples = await WaveformGenerator.generateWaveformSamples(from: url)
                await MainActor.run { self.waveformSamples = samples; self.isLoadingWaveform = false }
            }
        } catch { print("Error loading audio: \(error.localizedDescription)") }
    }

    func play() { audioPlayer?.play(); isPlaying = true; startTimer() }
    func pause() { audioPlayer?.pause(); isPlaying = false; stopTimer() }
    func seek(to time: TimeInterval) { audioPlayer?.currentTime = time; currentTime = time }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentTime = self.audioPlayer?.currentTime ?? 0
            if self.currentTime >= self.duration { self.pause(); self.seek(to: 0) }
        }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    func cleanup() { stopTimer(); audioPlayer?.stop(); audioPlayer = nil }
    deinit { cleanup() }
}

struct WaveformView: View {
    let samples: [Float], currentTime: TimeInterval, duration: TimeInterval, isLoading: Bool
    var onSeek: (Double) -> Void
    @State private var isHovering = false
    @State private var hoverLocation: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if isLoading {
                    HStack { ProgressView().controlSize(.small); Text("Loading...").font(.caption).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0.5) {
                        ForEach(0..<samples.count, id: \.self) { i in
                            Capsule()
                                .fill(CGFloat(i) / CGFloat(samples.count) <= CGFloat(currentTime / duration) ? Color.primary : Color.primary.opacity(0.3))
                                .frame(width: max((geo.size.width / CGFloat(samples.count)) - 0.5, 1), height: max(CGFloat(samples[i]) * 24, 2))
                        }
                    }.opacity(0.6).frame(maxHeight: .infinity)
                    if isHovering {
                        Text((duration * Double(hoverLocation / geo.size.width)).formatMinutesSeconds())
                            .font(.caption).monospacedDigit().foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: max(0, min(hoverLocation - 25, geo.size.width - 50)), y: -26)
                        Rectangle().fill(Color.accentColor).frame(width: 2).frame(maxHeight: .infinity).offset(x: hoverLocation)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if !isLoading { hoverLocation = value.location.x; onSeek(Double(value.location.x / geo.size.width) * duration) }
            })
            .onHover { h in if !isLoading { withAnimation { isHovering = h } } }
            .onContinuousHover { phase in if !isLoading, case .active(let loc) = phase { hoverLocation = loc.x } }
        }.frame(height: 32)
    }

}

struct AudioPlayerView: View {
    let url: URL
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var isRetranscribing = false
    @State private var showRetranscribeSuccess = false
    @State private var showRetranscribeError = false
    @State private var errorMessage = ""
    @State private var showPromptPopover = false
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext

    private var transcriptionService: AudioTranscriptionService {
        AudioTranscriptionService(modelContext: modelContext, whisperState: whisperState)
    }

    private func flashStatus(success: Bool, message: String = "") {
        if success { showRetranscribeSuccess = true } else { errorMessage = message; showRetranscribeError = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showRetranscribeSuccess = false; showRetranscribeError = false }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            WaveformView(samples: playerManager.waveformSamples, currentTime: playerManager.currentTime,
                duration: playerManager.duration, isLoading: playerManager.isLoadingWaveform, onSeek: { playerManager.seek(to: $0) })
            HStack(spacing: 8) {
                Text(playerManager.currentTime.formatMinutesSeconds()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Button { NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path) } label: {
                        Image(systemName: "folder")
                    }.buttonStyle(.bordered).controlSize(.small).help("Show in Finder")
                    Button { playerManager.isPlaying ? playerManager.pause() : playerManager.play() } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    }.buttonStyle(.bordered).controlSize(.small)
                    Button { showPromptPopover.toggle() } label: {
                        Image(systemName: enhancementService.activePrompt?.icon ?? "sparkles")
                    }.buttonStyle(.bordered).controlSize(.small)
                    .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.4).help("Select enhancement prompt")
                    .popover(isPresented: $showPromptPopover, arrowEdge: .bottom) { EnhancementPromptPopover().environmentObject(enhancementService) }
                    Button { retranscribeAudio() } label: {
                        Group {
                            if isRetranscribing { ProgressView().controlSize(.small) }
                            else if showRetranscribeSuccess { Image(systemName: "checkmark").foregroundStyle(.green) }
                            else { Image(systemName: "arrow.clockwise") }
                        }
                    }.buttonStyle(.bordered).controlSize(.small).disabled(isRetranscribing).help("Retranscribe this audio")
                }
                Spacer()
                Text(playerManager.duration.formatMinutesSeconds()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .onAppear { playerManager.loadAudio(from: url) }
        .onDisappear { playerManager.cleanup() }
        .overlay(alignment: .top) {
            VStack {
                if showRetranscribeSuccess { Label("Retranscription successful", systemImage: "checkmark.circle.fill").font(.body).foregroundStyle(.green).padding() }
                if showRetranscribeError { Label(errorMessage.isEmpty ? "Retranscription failed" : errorMessage, systemImage: "exclamationmark.circle.fill").font(.body).foregroundStyle(.red).padding() }
            }
        }
    }

    private func retranscribeAudio() {
        guard let model = whisperState.currentTranscriptionModel else {
            flashStatus(success: false, message: "No transcription model selected"); return
        }
        isRetranscribing = true
        Task {
            do {
                let _ = try await transcriptionService.retranscribeAudio(from: url, using: model)
                await MainActor.run { isRetranscribing = false; flashStatus(success: true) }
            } catch {
                await MainActor.run { isRetranscribing = false; flashStatus(success: false, message: error.localizedDescription) }
            }
        }
    }
}
