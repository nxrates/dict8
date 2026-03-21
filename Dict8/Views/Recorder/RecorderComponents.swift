import SwiftUI

// MARK: - Scrolling Audio Visualizer

struct AudioVisualizer: View {
    let audioMeter: AudioMeter
    let color: Color
    let isActive: Bool

    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 1.5
    private let minBarHeight: CGFloat = 2
    private let sampleInterval: TimeInterval = 1.0 / 45

    @State private var samples: [Float] = []
    @State private var smoothedLevel: Float = 0
    @State private var lastSampleDate: Date = .distantPast
    @State private var wasActive = false

    var body: some View {
        GeometryReader { geo in
            let maxBars = max(1, Int(geo.size.width / (barWidth + barSpacing)))

            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let _ = updateSamples(date: context.date)
                let visible = isActive ? Array(samples.suffix(maxBars)) : idleBars(maxBars)

                HStack(spacing: barSpacing) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, sample in
                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(color)
                            .frame(width: barWidth, height: max(minBarHeight, CGFloat(sample) * geo.size.height))
                            .frame(height: geo.size.height)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func updateSamples(date: Date) {
        // Reset when transitioning to active
        if isActive && !wasActive {
            DispatchQueue.main.async {
                // Prefill with flat baseline bars (like iPhone recorder)
                let prefillCount = 200
                samples = Array(repeating: Float(minBarHeight / 44.0), count: prefillCount)
                smoothedLevel = 0
                lastSampleDate = date
                wasActive = true
            }
            return
        }
        if !isActive && wasActive {
            DispatchQueue.main.async { wasActive = false }
            return
        }

        guard isActive, date.timeIntervalSince(lastSampleDate) >= sampleInterval else { return }

        let raw = max(0, min(1, Float(audioMeter.averagePower)))
        // Aggressive curve: silence is near-zero, speech peaks hard
        let scaled = raw < 0.02 ? raw * 0.5 : pow(raw, 0.6) * 1.4
        let clamped = min(scaled, 1.0)
        var level = smoothedLevel

        // Raw — almost no smoothing, snappy peaks
        level = clamped

        DispatchQueue.main.async {
            smoothedLevel = level
            samples.append(level)
            if samples.count > 600 { samples.removeFirst(samples.count - 600) }
            lastSampleDate = date
        }
    }

    private func idleBars(_ count: Int) -> [Float] {
        Array(repeating: Float(minBarHeight / 44.0), count: count)
    }
}

// MARK: - Record Button

struct RecorderRecordButton: View {
    let isRecording: Bool, isProcessing: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(isProcessing ? Color.secondary : (isRecording ? .red : Color.secondary.opacity(0.5))).frame(width: 25, height: 25)
                if isProcessing { ProcessingIndicator(color: .white).frame(width: 16, height: 16) }
                else if isRecording { RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 9, height: 9) }
                else { Circle().fill(.white).frame(width: 9, height: 9) }
            }
        }.buttonStyle(.plain).disabled(isProcessing)
    }
}

// MARK: - Processing Indicator

struct ProcessingIndicator: View {
    @State private var rotation: Double = 0
    let color: Color
    var body: some View {
        Circle().trim(from: 0.1, to: 0.9).stroke(color, lineWidth: 1.7).frame(width: 16, height: 16)
            .rotationEffect(.degrees(rotation))
            .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { rotation = 360 } }
    }
}

// MARK: - Unified Status Display

struct RecorderStatusDisplay: View {
    let currentState: RecordingState
    let audioMeter: AudioMeter
    var menuBarHeight: CGFloat? = nil
    @ObservedObject var notificationManager: NotificationManager = .shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                waveformOrAnimation
                    .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 44)

                if let notification = notificationManager.activeNotification {
                    HStack(spacing: 5) {
                        Image(systemName: notificationManager.activeNotificationType.iconName)
                            .font(.caption2)
                            .foregroundColor(notificationManager.activeNotificationType.iconColor)
                        Text(notification)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .transition(.opacity)
                } else if let caption = captionText {
                    Text(caption)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
            .padding(.horizontal, 0)

            if notificationManager.activeNotification != nil {
                Rectangle()
                    .fill(notificationManager.activeNotificationType.iconColor.opacity(0.6))
                    .frame(height: 2)
                    .scaleEffect(x: max(0, notificationManager.notificationProgress), anchor: .leading)
                    .animation(.linear(duration: 0.1), value: notificationManager.notificationProgress)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentState)
    }

    private var captionText: String? {
        switch currentState {
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .enhancing: return "Enhancing"
        default: return nil
        }
    }

    @ViewBuilder
    private var waveformOrAnimation: some View {
        switch currentState {
        case .recording:
            AudioVisualizer(audioMeter: audioMeter, color: .white, isActive: true)
        case .transcribing, .enhancing:
            ProcessingIndicator(color: .white)
        default:
            AudioVisualizer(audioMeter: audioMeter, color: .white.opacity(0.4), isActive: false)
        }
    }
}
